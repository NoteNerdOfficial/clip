// Creates an Asana task from the selection via the Asana REST API.
// Get a Personal Access Token at https://app.asana.com/0/my-apps -> Personal Access Tokens.
// Find your Workspace GID in the URL when browsing Asana in a web browser: app.asana.com/0/<workspaceGid>/...

function run(argv) {
  ObjC.import("Foundation");
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;

  const payload = JSON.parse(argv[0]);
  const text = (payload.text || "").trim();
  const options = payload.options || {};
  const token = options.accessToken || "";
  const workspaceGid = options.workspaceGid || "";

  if (!token || !text) {
    app.displayNotification("Add a Personal Access Token in Clip Preferences first.", { withTitle: "Asana: missing token" });
    return;
  }

  const body = { data: { name: text } };
  if (workspaceGid) body.data.workspace = workspaceGid;

  const stamp = Date.now();
  const bodyPath = `/tmp/clip-asana-body-${stamp}.json`;
  const responsePath = `/tmp/clip-asana-response-${stamp}.json`;

  const bodyStr = $.NSString.alloc.initWithUTF8String(JSON.stringify(body));
  bodyStr.writeToFileAtomicallyEncodingError(bodyPath, true, $.NSUTF8StringEncoding, null);

  // Body content is passed via a file (not shell-interpolated) since the
  // selected text may contain quotes, newlines, or other shell metacharacters.
  const cmd =
    `curl -s -o '${responsePath}' -w '%{http_code}' -X POST https://app.asana.com/api/1.0/tasks ` +
    `-H 'Authorization: Bearer ${token}' -H 'Content-Type: application/json' --data-binary @'${bodyPath}'`;

  let status, responseText;
  try {
    status = app.doShellScript(cmd);
    responseText = app.doShellScript(`cat '${responsePath}'`);
  } finally {
    app.doShellScript(`rm -f '${bodyPath}' '${responsePath}'`);
  }

  if (status.indexOf("2") !== 0) {
    throw new Error(`Asana API error ${status}: ${responseText}`);
  }

  app.displayNotification(text, { withTitle: "Task added to Asana" });
}
