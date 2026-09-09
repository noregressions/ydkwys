import { escape, startCase } from "lodash-es";

const output = document.querySelector("#result");
const button = document.querySelector("#load-info");

async function loadInfo() {
  output.textContent = "Loading…";

  const response = await fetch("./api/info?name=mixed%20supply%20chain");
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  const info = await response.json();
  const title = startCase(info.application);

  output.innerHTML = `
    <h2>${escape(title)}</h2>
    <dl>
      <dt>Message</dt><dd>${escape(info.message)}</dd>
      <dt>Java library</dt><dd>${escape(info.javaLibrary)}</dd>
      <dt>Runtime</dt><dd>${escape(info.server)}</dd>
    </dl>
  `;
}

button.addEventListener("click", () => {
  loadInfo().catch((error) => {
    output.textContent = `Failed to load runtime information: ${error.message}`;
  });
});

loadInfo().catch((error) => {
  output.textContent = `Failed to load runtime information: ${error.message}`;
});
