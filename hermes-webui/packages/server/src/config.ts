import { resolve } from 'path'
import { homedir } from 'os'

export const config = {
  port: parseInt(process.env.PORT || '8648', 10),
  host: process.env.HOST || '127.0.0.1',
  upstream: process.env.UPSTREAM || 'http://127.0.0.1:8642',
  uploadDir: process.env.UPLOAD_DIR || resolve(homedir(), '.hermes-web-ui', 'upload'),
  dataDir: process.env.HERMES_WEBUI_DATA_DIR || resolve(__dirname, '..', 'data'),
  corsOrigins: process.env.CORS_ORIGINS || '*',
}
