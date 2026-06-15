$(document).ready(function () {
  if (window.location.pathname != "/cgi-bin/koha/acqui/edifactmsgs.pl") return;

  let htmlLang = document.documentElement.lang || 'en';
  htmlLang = htmlLang.split('-')[0];
  if (!['en', 'fi', 'sv'].includes(htmlLang)) {
    htmlLang = 'en';
  }

  var checkExist = setInterval(function () {
    var $actions = $("td.actions");
    if ($actions.length > 0 && !$actions.first().find(".editx-btn").length) {
      clearInterval(checkExist);
      $actions.each(function () {
        var messageId = $(this).find('input[name="message_id"]').val();
        if (messageId) {
          $(this).prepend(
            '<button type="button" class="editx-btn btn btn-sm btn-secondary" style="margin-left:5px;" onclick="runEditxMessage(' + messageId + ')\">' +
            {
              en: "Re-run",
              fi: "Aja uudelleen",
              sv: "Kör igen"
            }[htmlLang] +
            '</button>'
          );
        }
      });
    }
  }, 100);
});

function runEditxMessage(messageId) {
  var button = $("button[onclick*=" + messageId + "]");
  button.attr("disabled", true);

  let htmlLang = document.documentElement.lang || 'en';
  htmlLang = htmlLang.split('-')[0];
  if (!['en', 'fi', 'sv'].includes(htmlLang)) {
    htmlLang = 'en';
  }

  button.text({
    en: "Running...",
    fi: "Ajetaan...",
    sv: "Kör..."
  }[htmlLang]);

  $.ajax({
    url: "/api/v1/contrib/kohasuomi/editx/" + messageId,
    type: "PUT",
    dataType: "json",
    contentType: "application/json; charset=utf-8",
    data: JSON.stringify({ status: "NEW" }),
    beforeSend: function () {},
    success: function (result) {
      location.reload();
    },
    error: function (xhr, status, error) {
      button.attr("disabled", false);
      button.text({
        en: "Re-run",
        fi: "Aja uudelleen",
        sv: "Kör igen"
      }[htmlLang]);
      console.error("Error: " + (JSON.parse(xhr.responseText).error || "Unknown error"));
    },
  });
}
