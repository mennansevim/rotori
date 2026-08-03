import { Client } from "ssh2";

export interface PiDeployConfig {
  host: string;
  user: string;
  password: string;
  repoDir: string;
  deployCmd: string;
  port?: number;
}

export interface PiDeployConfigResult {
  config?: PiDeployConfig;
  missing: string[];
}

export function loadPiConfig(env: NodeJS.ProcessEnv = process.env): PiDeployConfigResult {
  const required = ["PI_HOST", "PI_USER", "PI_PASSWORD", "PI_REPO_DIR", "PI_DEPLOY_CMD"] as const;
  const missing = required.filter((k) => !env[k] || !env[k]!.trim());
  if (missing.length > 0) return { missing };

  return {
    missing: [],
    config: {
      host: env.PI_HOST!.trim(),
      user: env.PI_USER!.trim(),
      password: env.PI_PASSWORD!,
      repoDir: env.PI_REPO_DIR!.trim(),
      deployCmd: env.PI_DEPLOY_CMD!,
      port: env.PI_PORT ? Number(env.PI_PORT) : 22,
    },
  };
}

function quoteForShell(s: string): string {
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

export interface DeployResult {
  exitCode: number;
  signal?: string;
}

export async function runOnPi(config: PiDeployConfig): Promise<DeployResult> {
  const remoteCmd = `cd ${quoteForShell(config.repoDir)} && ${config.deployCmd}`;

  return new Promise((resolve, reject) => {
    const conn = new Client();
    conn
      .on("ready", () => {
        conn.exec(remoteCmd, { pty: true }, (err, stream) => {
          if (err) {
            conn.end();
            return reject(err);
          }
          stream
            .on("close", (code: number | null, signal: string | null) => {
              conn.end();
              resolve({
                exitCode: typeof code === "number" ? code : 1,
                signal: signal ?? undefined,
              });
            })
            .on("data", (data: Buffer) => {
              process.stdout.write(data);
            })
            .stderr.on("data", (data: Buffer) => {
              process.stderr.write(data);
            });
        });
      })
      .on("error", (err) => reject(err))
      .connect({
        host: config.host,
        port: config.port ?? 22,
        username: config.user,
        password: config.password,
        readyTimeout: 15_000,
        keepaliveInterval: 10_000,
      });
  });
}
