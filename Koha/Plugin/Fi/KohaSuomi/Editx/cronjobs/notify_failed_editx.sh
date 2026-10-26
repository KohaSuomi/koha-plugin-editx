#!/bin/sh
# Send e-mail notifications of failed EDItX processing to people defined in plugin configuration.
# Written by Kodo Korkalo / Koha-Suomi Oy, GNU GPL3 or later applies.

die() { printf '%s\n' "$*" ; exit 1 ; }

# Get, set and check variables

export xmllint="$(which xmllint)"
test -n "$xmllint" || die "No xmllint, apt install libxml2-utils."

mailer="$(which mail)"
test -n "$mailer" || die "No mail, apt install heirloom-mailx."

test -e "$KOHA_CONF" || die "No KOHA_CONF."

# Need to de-reference $0 if it's a symlink for config exporter to work
test -h "$0" && script_realname="$(readlink -f "$0")" || script_realname="$0"

config_loader="$(dirname "$script_realname")/exportEditXConfig.pl"
test -e "$config_loader" || die "No EDItX config exporter $config_loader."
config_exports="$("$config_loader")" || die "Could not read EDItX plugin configuration."
eval "$config_exports"

failed_loader="$(dirname "$script_realname")/get_failed_editx_messages.pl"
test -e "$failed_loader" || die "No EDItX failed message reporter $failed_loader."
db_failed_messages="$("$failed_loader")" || die "Could not read EDItX failed messages from database."

test -n "$mailfrom" && mailfrom="-r $mailfrom"
test -n "$mailto" || die "No one to send notifications to in EDItX plugin configuration."
mailto_addresses="$(printf '%s\n' "$mailto" | tr ',' ' ')"

test -n "$tmp_path" || die "No path to incoming EDItX messages in plugin configuration."
test -n "$failed_path" || die "No path to failed EDItX messages in plugin configuration."
test -n "$failed_archived_path" || die "No path to failed_archived EDItX messages in plugin configuration."
test -n "$log_path" || die "No path to logs in $KOHA_CONF."

# Reported failed files are moved to failed_archived_path after the mail has
# been sent, so that the same file is not reported again on the next run.
archive_after_send="$log_path/editx/notify_failed_editx.archive.$$"
trap 'rm -f "$archive_after_send"' 0 1 2 3 15
: > "$archive_after_send" || die "Could not write archive list $archive_after_send."

# Encode a UTF-8 subject as RFC 2047 encoded words. A subject is split at
# character boundaries so that each encoded word stays below the 75 character
# limit of RFC 2047.
encode_subject() {
  printf '%s' "$1" | perl -MEncode=encode -MMIME::Base64=encode_base64 -CSD -e '
    my $text = do { local $/; <STDIN> };
    my @words;
    my $chunk = q{};
    for my $char (split //, $text) {
      my $bytes = encode("UTF-8", $char);
      if (length($chunk) + length($bytes) > 45) {
        push @words, "=?UTF-8?B?" . encode_base64($chunk, q{}) . "?=";
        $chunk = q{};
      }
      $chunk .= $bytes;
    }
    push @words, "=?UTF-8?B?" . encode_base64($chunk, q{}) . "?=" if length $chunk;
    print join(" ", @words);
  '
}

send_mail() {
  subject="$(encode_subject "$1")"
  "$mailer" $mailfrom -a "Content-Type: text/plain; charset=UTF-8" -s "$subject" $mailto_addresses
}

# Print the name the message has in Koha, so that a file from the fail folder
# can be found on the EDI messages page. runEditXImport constructs the name
# from ShipNoticeNumber and IssueDateTime.
print_koha_filename() {
  file="$1"
  base="$(basename "$file")"

  ship_notice_number="$("$xmllint" --xpath 'string(/*/Header/ShipNoticeNumber)' "$file" 2> /dev/null)"
  issue_date_time="$("$xmllint" --xpath 'string(/*/Header/IssueDateTime)' "$file" 2> /dev/null)"

  if test -n "$ship_notice_number" && test -n "$issue_date_time"; then
    koha_filename="${ship_notice_number}_${issue_date_time}"
    if test "$koha_filename" != "$base"; then
      printf "Sanoman nimi Kohassa: %s\n\n" "$koha_filename"
    fi
  fi
}

print_error_log_excerpt() {
  file="$1"
  lines="$2"

  if test -f "$log_path/editx/error.log"; then
    error_excerpt="$(grep -F --text -- "$(basename "$file")" "$log_path/editx/error.log" 2> /dev/null | tail -n "$lines")"
  else
    error_excerpt=""
  fi

  if test -n "$error_excerpt"; then
    printf '%s\n' "$error_excerpt"
  else
    printf "Virhelokista ei löytynyt tätä tiedostoa koskevaa riviä.\n"
  fi
}

# Get EDItX errors related to Elasticsearch and send emails

export result="$( grep -B 1 --text Elasticsearch "$log_path/editx/error.log" 2> /dev/null)"
if test -n "$result"; then
  if ! (
    printf "\nSeuraavat EDItX sanomat on saatettu käsitellä tuplasti (Elasticsearch-virhe):\n\n"
    printf '%s\n' "$result"

    printf "\n"
    printf "Katso lisätietoja EDItX rajapinnan parametroinnista ja tyypillisten virhetilanteiden korjaamisesta:\n"
    printf "https://koha-suomi.fi/dokumentaatio/editx/#43-erilaisia-virhetilanteita.\n"
  ) | send_mail "EDItX tilaussanomien käsittelyssä oli ongelmia (Elasticsearch)"; then
    die "Could not send EDItX Elasticsearch notification."
  fi
fi

# Get postponed and failed EDItX notices and send emails

export pending_files="$(ls -1 "$tmp_path"/*.xml 2> /dev/null)"
export failed_files="$(ls -1 "$failed_path"/*.xml 2> /dev/null)"

test -z "$pending_files" && test -z "$failed_files" && test -z "$db_failed_messages" && exit 0 # Exit if nothing to report

if ! (
  if test -n "$pending_files"; then

    printf "\nSeuraavat EDItX sanomat odottavat edelleen käsittelyä:\n\n"

    printf "Sanomien muodostamisessa aineistontoimittajan järjestelmässä tai niiden siirrossa Koha-palvelimelle\n"
    printf "on tapahtunut virhe, tai siirto palvelimelle on edelleen kesken.\n\n"

    for file in $pending_files; do

      printf "Ote rajapinnan virhelokista ($log_path/editx/error.log):\n"
      print_error_log_excerpt "$file" 1

      if test $(stat -c %Y "$file") -lt $(($(date +%s) - 604800)); then
        printf "Sanoma $file vanhentunut ja se -hylätään-. Arkistoidaan hakemistoon $failed_archived_path.\n"
        mv "$file" "$failed_archived_path/"
      else
        printf "Sanoma $file on jätetty käsittelyjonoon ($tmp_path) odottamaan täydennystä.\n"
      fi

      printf "\n"

    done

  fi

  if test -n "$failed_files"; then

    printf "Seuraavien EDItX sanomien käsittelyssä oli ongelmia:\n"

    for file in $failed_files; do

      printf "\n=== Sanoma: %s ===\n\n" "$(basename "$file")"
      print_koha_filename "$file"

      printf "Ote rajapinnan virhelokista ($log_path/editx/error.log):\n"
      print_error_log_excerpt "$file" 20

      unset affected_locations
      for location in $("$xmllint" --xpath "*/ItemDetail/CopyDetail/DeliverToLocation" "$file" 2> /dev/null | sed 's/<\/*DeliverToLocation\/*>/\n/ig' | sort -u); do
        affected_locations="$affected_locations $location"
      done

      if test -n "$affected_locations"; then
        printf "\nSanoma koskee sijainteja/tilejä:$affected_locations\n"
      else
        printf "\nSijoitus- ja tilitietoja ei löytynyt sanomasta.\n"
      fi

      if ! "$xmllint" --noout "$file" 2> /dev/null ; then
        printf "\nSanoma on formaatiltaan virheellinen."
        mv "$file" "$failed_archived_path/"
        continue
      fi

      # Archive the file only after the notification has been sent.
      printf '%s\n' "$file" >> "$archive_after_send"

    done

    printf "\nRaportoidut sanomat siirretään ilmoituksen lähettämisen jälkeen hakemistoon %s.\n" "$failed_archived_path"

  fi

  if test -n "$db_failed_messages"; then

    printf "\nSeuraavat EDItX sanomat ovat epäonnistuneet käsittelyssä (edifact_messages, status FAILED):\n\n"
    printf '%s\n' "$db_failed_messages"
    printf "\nVoit ajaa nämä uudelleen EDI-sanomat-sivun \"Aja uudelleen\" -painikkeella.\n\n"

  fi

  printf "Katso lisätietoja EDItX rajapinnan parametroinnista ja tyypillisten virhetilanteiden korjaamisesta:\n"
  printf "https://koha-suomi.fi/dokumentaatio/editx/#43-erilaisia-virhetilanteita.\n"

) | send_mail "EDItX tilaussanomien käsittelyssä oli ongelmia"; then
  die "Could not send EDItX notification."
fi

if test -s "$archive_after_send"; then
  while IFS= read -r file; do
    test -f "$file" || continue
    mv "$file" "$failed_archived_path/" || die "Could not archive failed message $file."
  done < "$archive_after_send"
fi

# All done, exit gracefully
exit 0
