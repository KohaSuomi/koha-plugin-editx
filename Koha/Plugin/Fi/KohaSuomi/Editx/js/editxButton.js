$(document).ready(function () {
  if (window.location.pathname != "/cgi-bin/koha/acqui/edifactmsgs.pl") return;
  var checkExist = setInterval(function () {
    var $actions = $("td.actions");
    if ($actions.length > 0 && !$actions.first().find(".editx-btn").length) {
      clearInterval(checkExist);
      $actions.each(function () {
        var messageId = $(this).find('input[name="message_id"]').val();
        if (messageId) {
          $(this).append(
            '<button type="button" class="editx-btn btn btn-sm btn-secondary" style="margin-left:5px;" onclick="runEditxMessage(' + messageId + ')\">Re-run</button>'
          );
        }
      });
    }
  }, 100);
});

function runEditxMessage(messageId) {
  var button = $("button[onclick*=" + messageId + "]");
  button.attr("disabled", true);
  button.text("Running...");
  
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
      button.text("Re-run");
      console.error("Error: " + (JSON.parse(xhr.responseText).error || "Unknown error"));
    },
  });
}
