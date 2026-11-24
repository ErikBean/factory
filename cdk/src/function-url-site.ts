// A static website served over HTTPS by a Lambda function URL, with no
// CloudFront distribution or S3 bucket. For accounts AWS hasn't yet verified
// for CloudFront, which new accounts must be, and which also can't create
// Amplify apps. The site's files are bundled into the function, so each
// deploy replaces them. A function URL can't take a custom domain, and
// responses are limited to 6 MB, so keep it to small sites. Move to
// StaticSite once the account is verified: the URL changes, so installed web
// apps need installing again.
import { Duration, RemovalPolicy } from "aws-cdk-lib";
import { Code, Function, FunctionUrlAuthType, Runtime } from "aws-cdk-lib/aws-lambda";
import { LogGroup, RetentionDays } from "aws-cdk-lib/aws-logs";
import { Construct } from "constructs";
import { cpSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FactoryStack } from "./factory-stack";

export interface FunctionUrlSiteProps {
  /** The folder whose files are published, such as "site" or "dist". */
  readonly source: string;
  /** The page served for "/" and other folder paths. Defaults to index.html. */
  readonly indexDocument?: string;
}

/**
 * The function's handler: serves the bundled site/ folder, an index document
 * for folder paths and 404 for anything else, including paths outside site/.
 * Exported for tests.
 */
export function functionUrlSiteHandler(indexDocument: string): string {
  return `// Serves ./site over a Lambda function URL. Written by @favabean/factory-cdk's FunctionUrlSite.
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";

const root = join(process.env.LAMBDA_TASK_ROOT ?? process.cwd(), "site");
const index = ${JSON.stringify(indexDocument)};
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json",
  ".webmanifest": "application/manifest+json",
  ".txt": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
  ".mp3": "audio/mpeg",
  ".ogg": "audio/ogg",
  ".wav": "audio/wav",
};

export const handler = async (event) => {
  let path;
  try { path = decodeURIComponent(event.rawPath || "/"); } catch { return notFound(); }
  if (path.endsWith("/")) path += index;
  const file = normalize(join(root, path));
  if (!file.startsWith(root + "/")) return notFound();
  let body;
  try { body = await readFile(file); } catch { return notFound(); }
  const type = types[extname(file).toLowerCase()] ?? "application/octet-stream";
  const binary = !/^text\\/|json|svg/.test(type);
  return {
    statusCode: 200,
    headers: { "content-type": type, "cache-control": "no-cache", "x-content-type-options": "nosniff" },
    body: body.toString(binary ? "base64" : "utf8"),
    isBase64Encoded: binary,
  };
};

function notFound() {
  return { statusCode: 404, headers: { "content-type": "text/plain; charset=utf-8" }, body: "Not found" };
}
`;
}

export class FunctionUrlSite extends Construct {
  public readonly function: Function;
  public readonly url: string;

  constructor(scope: FactoryStack, id: string, props: FunctionUrlSiteProps) {
    super(scope, id);
    const bundle = mkdtempSync(join(tmpdir(), "function-url-site-"));
    writeFileSync(join(bundle, "index.mjs"), functionUrlSiteHandler(props.indexDocument ?? "index.html"));
    cpSync(props.source, join(bundle, "site"), { recursive: true });

    this.function = new Function(this, "Function", {
      runtime: Runtime.NODEJS_24_X,
      handler: "index.handler",
      code: Code.fromAsset(bundle),
      memorySize: 128,
      timeout: Duration.seconds(5),
      logGroup: new LogGroup(this, "Logs", {
        retention: scope.stage.ephemeral ? RetentionDays.ONE_DAY : RetentionDays.ONE_MONTH,
        removalPolicy: RemovalPolicy.DESTROY,
      }),
    });
    // NONE: anyone can load the site, as with a public CloudFront site.
    this.url = this.function.addFunctionUrl({ authType: FunctionUrlAuthType.NONE }).url;
    scope.addUrl(id, this.url);
  }
}
