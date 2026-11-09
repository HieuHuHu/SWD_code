import 'dotenv/config';

export const config = {
  port: Number(process.env.PORT ?? 4001),
  webOrigin: (process.env.WEB_ORIGIN ?? 'http://localhost:3001').split(','),
  db: {
    host: process.env.DB_HOST ?? 'localhost',
    port: Number(process.env.DB_PORT ?? 5432),
    user: process.env.DB_USER ?? 'autocare',
    password: process.env.DB_PASSWORD ?? 'autocare123',
    name: process.env.DB_NAME ?? 'autocare',
  },
  jwt: {
    secret: process.env.JWT_SECRET ?? 'autocare-dev-secret-change-me',
    expiresIn: process.env.JWT_EXPIRES_IN ?? '30m',      // NFR-5: 30-minute session
  },
};
