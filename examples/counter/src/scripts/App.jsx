import Stigma, { useState } from "stigma";

function App() {
  const [count, setCount] = useState(0);

  return (
    <Box orientation="vertical" spacing="12">
      <Label>{"Clicked " + count + " times!"}</Label>
      <Button onPress={function() { console.log("I was clicked!"); setCount(count + 1); }}>
        Click Me
      </Button>
    </Box>
  );
}

Stigma.onReady(function() {
  Stigma.render("root", App);
});