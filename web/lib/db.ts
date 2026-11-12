import sql from 'mssql';

const sqlConfig: sql.config = {
  server: process.env.DB_SERVER || 'localhost',
  port: process.env.DB_PORT ? Number(process.env.DB_PORT) : 1433,
  database: process.env.DB_DATABASE || 'AR_IMMS',
  user: process.env.DB_USER || 'sa',
  password: process.env.DB_PASSWORD || '',
  options: {
    encrypt: process.env.DB_ENCRYPT === 'true',
    trustServerCertificate: process.env.DB_TRUST_SERVER_CERTIFICATE !== 'false',
    enableArithAbort: true,
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
};

declare global {
  // eslint-disable-next-line no-var
  var _mssqlPool: Promise<sql.ConnectionPool> | undefined;
}

export function getPool(): Promise<sql.ConnectionPool> {
  if (!global._mssqlPool) {
    global._mssqlPool = new sql.ConnectionPool(sqlConfig).connect().catch((err) => {
      global._mssqlPool = undefined;
      throw err;
    });
  }
  return global._mssqlPool;
}

export type SpParamValue =
  | string
  | number
  | boolean
  | Date
  | null
  | undefined;

export interface SpParamDefinition {
  value: SpParamValue;
  type?: sql.ISqlType | (() => sql.ISqlType);
}

export type SpParams = Record<string, SpParamValue | SpParamDefinition>;

export async function callSp<T = any>(
  spName: string,
  params?: SpParams
): Promise<T[]> {
  const pool = await getPool();
  const request = pool.request();

  if (params) {
    for (const [key, raw] of Object.entries(params)) {
      if (raw && typeof raw === 'object' && 'value' in raw && 'type' in raw) {
        const def = raw as SpParamDefinition;
        if (def.type) {
          request.input(key, def.type as any, def.value ?? null);
        } else {
          request.input(key, def.value ?? null);
        }
      } else {
        request.input(key, (raw as SpParamValue) ?? null);
      }
    }
  }

  const result = await request.execute<T>(spName);
  return (result.recordset || []) as T[];
}

export async function pingDb(): Promise<boolean> {
  try {
    const pool = await getPool();
    const res = await pool.request().query('SELECT 1 AS alive');
    return res.recordset?.[0]?.alive === 1;
  } catch {
    return false;
  }
}
