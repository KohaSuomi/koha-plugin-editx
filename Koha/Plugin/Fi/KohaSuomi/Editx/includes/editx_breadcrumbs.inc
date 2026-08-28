[% WRAPPER 'sub-header.inc' %]
    [% WRAPPER breadcrumbs %]
        [% WRAPPER breadcrumb_item %]
            <a href="/cgi-bin/koha/plugins/plugins-home.pl?method=tool">[% T.configure_38 %]</a>
        [% END %]
        [% WRAPPER breadcrumb_item %]
            <a href="[% configure_href | html %]">[% T.configure_39 %]</a>
        [% END %]
        [% WRAPPER breadcrumb_item bc_active= 1 %]
            <span>[% T.configure_40 %]</span>
        [% END %]
    [% END #/ WRAPPER breadcrumbs %]
[% END #/ WRAPPER sub-header.inc %]
