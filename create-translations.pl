#!/usr/bin/env perl
# create-translations.pl
#
# Scans .tt template files in a Koha plugin for hardcoded visible strings,
# generates translation keys (page_name_1, page_name_2 ...), creates/updates
# i18n/*.inc translation files, and replaces strings in templates with
# [% T.key %] references.
#
# Works with any Koha plugin using the [% T.key %] / i18n/*.inc pattern.
#
# Usage: perl create-translations.pl [PLUGIN_ROOT]
#   PLUGIN_ROOT defaults to the directory containing this script.
#
# Translatable string candidates:
#   - Text nodes between HTML tags  (no [% or {{ inside)
#   - aria-label="..."  attribute values
#   - title="..."       attribute values  (skips link/meta/script elements)
#   - value="..."       on submit inputs / <button> elements
#
# Key format: <page_name>_<n>  (e.g. admin_editx_1, configure_3)
#   page_name = .tt filename without extension.
#   Same string seen again (in any file) reuses the existing key.
#
# .inc files created/updated: default.inc, fi-FI.inc, sv-SE.inc
# All language files receive the original string as the value (no translation).
# Existing keys/values in .inc files are NEVER overwritten.
# .tt files are backed up as .tt.bak before modification.

use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use File::Find ();
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use Cwd qw(abs_path);

my $plugin_root = $ARGV[0] // do {
    my $script = abs_path($0);
    dirname($script);
};

# 1. Find .tt files
my @tt_files;
my $koha_dir = "$plugin_root/Koha";
die "No Koha/ directory under $plugin_root\n" unless -d $koha_dir;

File::Find::find(
    { wanted => sub { push @tt_files, $File::Find::name if /\.tt$/ }, no_chdir => 1 },
    $koha_dir
);
die "No .tt files found under $koha_dir\n" unless @tt_files;
@tt_files = sort @tt_files;

print "Found " . scalar(@tt_files) . " .tt file(s):\n";
print "  $_\n" for @tt_files;
print "\n";

# 2. Determine i18n directory (alongside the .tt files)
my $tt_dir = dirname($tt_files[0]);
for my $f (@tt_files) {
    my $d = dirname($f);
    while ($tt_dir ne $d) {
        if (length($tt_dir) >= length($d)) { $tt_dir = dirname($tt_dir) }
        else                               { $d      = dirname($d)      }
    }
}
my $i18n_dir = "$tt_dir/i18n";
mkdir $i18n_dir unless -d $i18n_dir;
print "i18n directory: $i18n_dir\n\n";

# 3. String validation
sub is_translatable {
    my ($text) = @_;
    return 0 unless defined $text;
    $text =~ s/^\s+|\s+$//g;
    return 0 unless length($text) >= 2;
    return 0 if $text =~ /\[%|\{\{/;
    return 0 if $text =~ /^[0-9\s\.\,\:\;\-\/\(\)!]+$/;
    return 0 if $text =~ /^https?:\/\//;
    return 0 if $text =~ /_/ && $text !~ /\s/;
    return 0 if $text =~ /,/ && $text !~ /\s/;
    return 0 unless $text =~ /[a-zA-Z\x{00C0}-\x{024F}]/;
    return 0 if $text =~ /=["']/;          # HTML/Vue attribute fragment
    return 0 if $text =~ /^(?:@|:|v-)/;   # Vue directive/binding (@click, :class, v-if)
    return 0 if $text =~ /^(?:&[a-zA-Z]+;|&#x?[0-9a-fA-F]+;|\s)+$/;  # Only HTML entities
    return 1;
}

# 4. Extract strings with page_name_N key generation
my %string_to_key;
my %key_to_string;
my @discovery_order;
my %page_counter;

# Split text on [%...%] or {{...}} blocks and register each clean segment
sub extract_and_register {
    my ($text, $page_name) = @_;
    if ($text =~ /\[%/) {
        for my $seg (split /\[%[^%]*%\]/, $text) {
            register_string($seg, $page_name);
        }
    } elsif ($text =~ /\{\{/) {
        for my $seg (split /\{\{[^}]*\}\}/, $text) {
            register_string($seg, $page_name);
        }
    } else {
        register_string($text, $page_name);
    }
}

sub register_string {
    my ($raw, $page_name) = @_;
    (my $text = $raw) =~ s/^\s+|\s+$//g;
    return unless is_translatable($text);
    return if exists $string_to_key{$text};

    $page_counter{$page_name} = ($page_counter{$page_name} // 0) + 1;
    my $key = "${page_name}_$page_counter{$page_name}";

    $string_to_key{$text} = $key;
    $key_to_string{$key}  = $text;
    push @discovery_order, $text;
}

for my $tt_file (@tt_files) {
    my $page_name = basename($tt_file, '.tt');
    open(my $fh, '<:encoding(UTF-8)', $tt_file) or die "Cannot open $tt_file: $!";
    my $in_script = 0;
    my $in_style = 0;
    while (my $line = <$fh>) {
        chomp $line;
        # Track when we're inside <script> or <style> blocks
        $in_script = 1 if $line =~ /<script\b/i;
        $in_style = 1 if $line =~ /<style\b/i;
        $in_script = 0 if $line =~ /<\/script>/i;
        $in_style = 0 if $line =~ /<\/style>/i;
        
        # Skip extraction if we're inside script or style blocks
        next if $in_script || $in_style;
        
        while ($line =~ />([^<]+)/g) {
            extract_and_register($1, $page_name);
        }
        # Pure text node on its own line (no < or > on the line)
        if ($line !~ /[<>]/ && $line =~ /\S/) {
            extract_and_register($line, $page_name);
        }
        while ($line =~ /\baria-label="([^"]+)"/g) {
            register_string($1, $page_name);
        }
        if ($line !~ /<(?:link|meta|script)\b/i) {
            while ($line =~ /\btitle="([^"]+)"/g) {
                register_string($1, $page_name);
            }
        }
        if ($line =~ /type=["']submit["']/ || $line =~ /<button\b/i) {
            while ($line =~ /\bvalue="([^"]+)"/g) {
                register_string($1, $page_name);
            }
        }
    }
    close($fh);
}

printf "Discovered %d unique translatable string(s):\n\n", scalar(@discovery_order);
for my $str (@discovery_order) {
    printf "  %-44s => %s\n", qq{"$str"}, $string_to_key{$str};
}
print "\n";

# 5. .inc file helpers
sub load_inc_keys {
    my ($file) = @_;
    my %keys;
    return %keys unless -f $file;
    open(my $fh, '<:encoding(UTF-8)', $file) or die "Cannot read $file: $!";
    while (<$fh>) {
        $keys{$1} = $2 if /^\s+(\w+)\s*=\s*["'](.+?)["']\s*,?\s*(?:#.*)?$/;
    }
    close($fh);
    return %keys;
}

sub write_inc_full {
    my ($file, $ordered_keys_ref, $kts_ref) = @_;
    open(my $fh, '>:encoding(UTF-8)', $file) or die "Cannot write $file: $!";
    print  $fh "[%\n    T = {\n";
    for my $key (@$ordered_keys_ref) {
        (my $val = $kts_ref->{$key}) =~ s/"/\\"/g;
        printf $fh "        %-42s = \"%s\",\n", $key, $val;
    }
    print  $fh "    }\n%]\n";
    close($fh);
}

sub update_inc {
    my ($file, $new_keys_ref, $kts_ref) = @_;
    return unless @$new_keys_ref;
    open(my $fh, '<:encoding(UTF-8)', $file) or die "Cannot read $file: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    my $insert = '';
    for my $key (@$new_keys_ref) {
        (my $val = $kts_ref->{$key}) =~ s/"/\\"/g;
        $insert .= sprintf("        %-42s = \"%s\", # NEW\n", $key, $val);
    }
    $content =~ s/^(    \})/\n$insert$1/m;
    open(my $out, '>:encoding(UTF-8)', $file) or die "Cannot write $file: $!";
    print $out $content;
    close($out);
}

# 6. Write / update all three .inc files
my @ordered_keys = map { $string_to_key{$_} } @discovery_order;

for my $lang ('default', 'fi-FI', 'sv-SE') {
    my $file = "$i18n_dir/$lang.inc";
    if (!-f $file) {
        write_inc_full($file, \@ordered_keys, \%key_to_string);
        print "Created:    $file\n";
    } else {
        my %existing = load_inc_keys($file);
        my @new_keys = grep { !exists $existing{$_} } @ordered_keys;
        if (@new_keys) {
            update_inc($file, \@new_keys, \%key_to_string);
            printf "Updated:    %s  (+%d key(s))\n", $file, scalar(@new_keys);
        } else {
            print "Up-to-date: $file\n";
        }
    }
}
print "\n";

# 7. Patch .tt files
my @sorted_strings = sort { length($b) <=> length($a) } @discovery_order;

my $try_block = "[% TRY %]\n    [% PROCESS \"\$PLUGIN_DIR/i18n/\${LANG}.inc\" %]\n[% CATCH %]\n    [% PROCESS \"\$PLUGIN_DIR/i18n/default.inc\" %]\n[% END %]\n";

for my $tt_file (@tt_files) {
    open(my $fh, '<:encoding(UTF-8)', $tt_file) or die "Cannot read $tt_file: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    my $original = $content;

    for my $str (@sorted_strings) {
        next unless length($str) >= 3;
        my $key = $string_to_key{$str};
        next if index($content, $str) < 0;

        $content =~ s{(?<=>)\s*\Q$str\E\s*(?=<|\[%)}{[% T.$key %]}g;
        $content =~ s{(?<=>)\s*\Q$str\E\s*$}{[% T.$key %]}mg;
        # Pure text node on its own line (no < or > on that line)
        $content =~ s{^(\s*)\Q$str\E(\s*)$}{$1\[% T.$key %\]$2}mg;
        # Static segment before first {{ on a line
        $content =~ s{^(\s+)\Q$str\E(\s+\{\{)}{$1\[% T.$key %\]$2}mg;
        # Static segment after last }} on a line
        $content =~ s{(\}\}\s+)\Q$str\E(\s*)$}{$1\[% T.$key %\]$2}mg;
        # Static segment between }} and {{ on a line
        $content =~ s{(\}\}[^{<\n]*)\Q$str\E([^}<\n]*\{\{)}{$1\[% T.$key %\]$2}mg;
        # Static text between TT directives ([% ... %]text[% ... %])
        $content =~ s{(%\]\s*)\Q$str\E(\s*\[%)}{$1\[% T.$key %\]$2}g;
        $content =~ s{\baria-label="\Q$str\E"}{aria-label="[% T.$key %]"}g;
        $content =~ s{\btitle="\Q$str\E"}{title="[% T.$key %]"}g;
        $content =~ s{\bvalue="\Q$str\E"}{value="[% T.$key %]"}g;
    }

    if ($content ne $original) {
        $content = $try_block . $content unless $content =~ /\[%\s*TRY\s*%\]/;
        copy($tt_file, "$tt_file.bak") or die "Cannot backup $tt_file: $!";
        open(my $out, '>:encoding(UTF-8)', $tt_file) or die "Cannot write $tt_file: $!";
        print $out $content;
        close($out);
        print "Modified:   $tt_file\n             (backup: $tt_file.bak)\n";
    } else {
        print "No changes: $tt_file\n";
    }
}

print "\nDone.\n";
