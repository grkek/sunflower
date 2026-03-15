function LoginPage({ onLogin, onNavigate }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  async function handleLogin() {
    if (!username || !password) {
      setError("Please fill in all fields");
      return;
    }

    setLoading(true);
    setError(null);

    const res = await $.http.post("https://dummyjson.com/auth/login",
      JSON.stringify({
        username: username,
        password: password,
        expiresInMins: 30
      }),
      { "Content-Type": "application/json" }
    );

    setLoading(false);

    if (res.error) {
      setError("Request failed: " + res.error);
      return;
    }

    const data = JSON.parse(res.body);
    if (data.accessToken) {
      onLogin(data);
    } else {
      setError(data.message || "Login failed");
    }
  }

  return (
    <Box orientation="vertical" className="form-wrapper" horizontalAlignment="center">
      <Label className="app-title">Sunflower</Label>
      <Label className="app-subtitle">Sign in to continue</Label>
      <HorizontalSeparator className="divider" />
      <Label className="field-label">Username</Label>
      <Entry className="field-input" onChange={function(text) { setUsername(text); }} />
      <Label className="field-label">Password</Label>
      <Entry className="field-input" inputType="password" onChange={function(text) { setPassword(text); }} />
      {error ? <Label className="error-label">{error}</Label> : null}
      <Button className="primary-button" onPress={handleLogin}>
        {loading ? "Signing in..." : "Sign In"}
      </Button>
      <HorizontalSeparator className="divider-thin" />
      <Button className="secondary-button" onPress={function() { onNavigate("register"); }}>
        Create Account
      </Button>
    </Box>
  );
}

function RegisterPage({ onNavigate }) {
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState(null);

  function handleRegister() {
    if (!username || !email || !password || !confirm) {
      setError("Please fill in all fields");
      return;
    }
    if (password !== confirm) {
      setError("Passwords do not match");
      return;
    }
    console.log("Register: " + username + " (" + email + ")");
  }

  return (
    <Box orientation="vertical" className="form-wrapper" horizontalAlignment="center">
      <Label className="app-title">Sunflower</Label>
      <Label className="app-subtitle">Create your account</Label>
      <HorizontalSeparator className="divider" />
      <Label className="field-label">Username</Label>
      <Entry className="field-input" onChange={function(text) { setUsername(text); }} />
      <Label className="field-label">Email</Label>
      <Entry className="field-input" onChange={function(text) { setEmail(text); }} />
      <Label className="field-label">Password</Label>
      <Entry className="field-input" inputType="password" onChange={function(text) { setPassword(text); }} />
      <Label className="field-label">Confirm Password</Label>
      <Entry className="field-input" inputType="password" onChange={function(text) { setConfirm(text); }} />
      {error ? <Label className="error-label">{error}</Label> : null}
      <Button className="primary-button" onPress={handleRegister}>Create Account</Button>
      <HorizontalSeparator className="divider-thin" />
      <Button className="secondary-button" onPress={function() { onNavigate("login"); }}>
        Back to Sign In
      </Button>
    </Box>
  );
}

function WelcomePage({ user }) {
  return (
    <Box orientation="vertical" className="form-wrapper" horizontalAlignment="center">
      <Label className="app-title">Welcome!</Label>
      <Label className="app-subtitle">{user.firstName + " " + user.lastName}</Label>
      <HorizontalSeparator className="divider" />
      <Label className="field-label">{user.email}</Label>
    </Box>
  );
}

function App() {
  const [page, setPage] = useState("login");
  const [user, setUser] = useState(null);

  function handleLogin(userData) {
    setUser(userData);
    setPage("welcome");
  }

  if (page === "welcome" && user) {
    return <WelcomePage user={user} />;
  }

  if (page === "register") {
    return <RegisterPage onNavigate={setPage} />;
  }

  return <LoginPage onLogin={handleLogin} onNavigate={setPage} />;
}

// Mount the app
$.onReady(function() {
  $.render("root", App);
});