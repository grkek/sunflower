$.onReady(async () => {
  $.getComponentById("joinButton").on.press = function () {
    var username = $.getComponentById("usernameEntry").getText();
    var password = $.getComponentById("passwordEntry").getText();

    if (!username || !password) {
      console.warn("Please fill in all fields");
      return;
    }

    console.log("Signing in as: " + username);
  };

  $.getComponentById("registerButton").on.press = function () {
    console.log("Navigate to registration");
  };
});

$.onExit(async () => {
  console.log("Goodbye!");
});