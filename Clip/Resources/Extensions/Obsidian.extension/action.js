// Creates or appends to a note in Obsidian via the free "Advanced URI"
// community plugin's URL scheme (obsidian://advanced-uri).

function run(argv) {
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;

  const payload = JSON.parse(argv[0]);
  const text = (payload.text || "").trim();
  const sourceApp = payload.sourceApp || "";
  const options = payload.options || {};

  const vaultName = options.vaultName || "";
  if (!vaultName || !text) {
    app.displayNotification("Set a Vault Name in Clip Preferences first.", { withTitle: "Obsidian: missing vault" });
    return;
  }

  const newFile = options.newFile === "true";
  const sourceLink = options.sourceLink !== "false"; // defaults on
  const includeTimestamp = options.includeTimestamp === "true";
  const fileName = options.fileName || "";
  const heading = options.heading || "";

  let content = (newFile ? "" : "\n") + text;
  if (sourceLink && sourceApp) {
    content += `\n(captured from ${sourceApp})`;
  }
  if (includeTimestamp) {
    const now = new Date();
    const hh = String(now.getHours()).padStart(2, "0");
    const mm = String(now.getMinutes()).padStart(2, "0");
    content = `- ${hh}:${mm} ${content}`;
  }

  const params = [`vault=${encodeURIComponent(vaultName)}`];
  if (fileName) {
    params.push(`filename=${encodeURIComponent(fileName)}`);
  } else {
    params.push(`daily=true`);
  }
  if (heading) {
    params.push(`heading=${encodeURIComponent(heading)}`);
  }
  params.push(`data=${encodeURIComponent(content)}`);
  params.push(`mode=${newFile ? "new" : "append"}`);

  const url = `obsidian://advanced-uri?${params.join("&")}`;
  app.openLocation(url);
}
