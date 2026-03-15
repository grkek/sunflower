const pages = {
  login: {
    subtitle: "Sign in to continue"
  },
  register: {
    subtitle: "Create your account"
  }
};

function navigate(page) {
  for (const key in pages) {
    $.getComponentById(key + "Page").setVisible(key === page);
  }
  $.getComponentById("pageSubtitle").setText(pages[page].subtitle);
}

$.onReady(async () => {
  navigate("login");

  $.getComponentById("signInButton").on.press = async function () {
    const username = $.getComponentById("loginUsername").getText();
    const password = $.getComponentById("loginPassword").getText();

    if (!username || !password) {
      console.warn("Please fill in all fields");
      return;
    }

    $.getComponentById("signInButton").setText("Signing in...");

    const res = await $.http.post("https://dummyjson.com/auth/login",
      JSON.stringify({
        username: username,
        password: password,
        expiresInMins: 30
      }),
      { "Content-Type": "application/json" }
    );

    if (res.error) {
      console.error("Request failed: " + res.error);
      $.getComponentById("signInButton").setText("Sign In");
      return;
    }

    const data = JSON.parse(res.body);

    if (data.token || data.accessToken) {
      console.log("Welcome, " + data.firstName + " " + data.lastName + "!");

      // Hide both pages
      $.getComponentById("loginPage").setVisible(false);
      $.getComponentById("registerPage").setVisible(false);

      $.getComponentById("pageTitle").setText("Welcome!");
      $.getComponentById("pageSubtitle").setText(data.firstName + " " + data.lastName);

      $.getComponentById("termsLabel").setVisible(false);
    } else {
      console.error("Login failed: " + (data.message || "Unknown error"));
      $.getComponentById("signInButton").setText("Sign In");
    }
  };

  $.getComponentById("goToRegister").on.press = function () {
    navigate("register");
  };

  $.getComponentById("goToLogin").on.press = function () {
    navigate("login");
  };
});

$.onExit(async () => { });