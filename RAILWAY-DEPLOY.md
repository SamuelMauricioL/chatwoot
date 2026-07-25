# 🚂 Manual de Deploy de Chatwoot en Railway

> **Versión**: 1.0
> **Repo fork**: `SamuelMauricioL/chatwoot`
> **Proyecto Railway**: `exemplary-presence`
> **URL**: `https://web-production-b5200.up.railway.app`

---

## Índice

1. [Requisitos previos](#1-requisitos-previos)
2. [Fork del repositorio](#2-fork-del-repositorio)
3. [Estructura de personalización `custom/`](#3-estructura-de-personalización-custom)
4. [Crear el proyecto en Railway](#4-crear-el-proyecto-en-railway)
5. [Configurar servicios](#5-configurar-servicios)
6. [Variables de entorno](#6-variables-de-entorno)
7. [Levantar Chatwoot por primera vez](#7-levantar-chatwoot-por-primera-vez)
8. [Problema conocido: migrations rotas](#8-problema-conocido-migrations-rotas)
9. [Configurar WhatsApp Embedded Signup](#9-configurar-whatsapp-embedded-signup)
10. [Conectar canales adicionales](#10-conectar-canales-adicionales)
11. [Mantenimiento y upgrades](#11-mantenimiento-y-upgrades)
12. [Resolución de problemas](#12-resolución-de-problemas)

---

## 1. Requisitos previos

- Cuenta en **GitHub**
- Cuenta en **Railway** (railway.app)
- **Railway CLI** instalado (`brew install railway` o desde el dashboard)
- **Docker Desktop** (para pruebas locales)
- Cuenta de **Meta Developer** (para WhatsApp)

---

## 2. Fork del repositorio

### 2.1. Hacer fork

1. Ir a https://github.com/chatwoot/chatwoot
2. Click en **Fork** → crear fork en tu cuenta
3. Clonar localmente:

```bash
git clone https://github.com/TU_USUARIO/chatwoot.git
cd chatwoot
git remote add upstream https://github.com/chatwoot/chatwoot.git
```

### 2.2. Rama recomendada

Trabajar siempre en `develop`:

```bash
git checkout develop
```

---

## 3. Estructura de personalización `custom/`

Para poder recibir actualizaciones del upstream sin conflictos, **todo el código custom va dentro de `custom/`**, sin modificar archivos del core.

### 3.1. Crear la estructura

```bash
mkdir -p custom/app/models/custom
mkdir -p custom/app/controllers/custom
mkdir -p custom/app/views
mkdir -p custom/lib/custom
mkdir -p custom/config/initializers
```

### 3.2. Configurar `config/application.rb`

Agregar al final del bloque `class Application < Rails::Application`:

```ruby
# ─── VendeEnOne Custom Extensions ───────────────────────────────────────────
if Rails.root.join('custom').exist?
  config.eager_load_paths << Rails.root.join('custom/lib')
  config.eager_load_paths += Dir["#{Rails.root}/custom/app/**"]
  config.paths['app/views'].unshift('custom/app/views')

  custom_initializers = Rails.root.join('custom/config/initializers')
  Dir[custom_initializers.join('**/*.rb')].each { |f| require f } if custom_initializers.exist?
end
```

### 3.3. Dockerfile para Railway

El `chatwoot/chatwoot:develop` viene con `CMD ["irb"]` (una consola de Ruby).  
Para Railway necesitamos sobrescribirlo con el comando de Rails:

```dockerfile
# Dockerfile (raíz del repo)
ARG CW_TAG=develop
FROM chatwoot/chatwoot:${CW_TAG}
COPY custom/ /app/custom/
COPY config/application.rb /app/config/application.rb
# Railway: sin entrypoint (pg_isready cuelga con DATABASE_URL de Railway)
CMD ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
```

### 3.4. railway.json

```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "DOCKERFILE",
    "dockerfilePath": "Dockerfile"
  },
  "deploy": {
    "numReplicas": 1,
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 10
  }
}
```

### 3.5. Commit inicial

```bash
git add custom/ Dockerfile railway.json config/application.rb
git commit -m "feat: add VendeEnOne custom extensions layer for Railway"
git push origin develop
```

---

## 4. Crear el proyecto en Railway

### 4.1. Autenticar CLI

```bash
railway login
```

### 4.2. Crear proyecto desde CLI

```bash
railway init
```

Seleccionar:
- Workspace: tu workspace personal
- Nombre: `chatwoot` (o el que prefieras)

Esto crea el proyecto vacío. Luego vincular:

```bash
railway link --project NOMBRE_DEL_PROYECTO
```

### 4.3. Crear servicios

Dentro del proyecto Railway, crear **4 servicios**:

| Servicio | Tipo | Propósito |
|---|---|---|
| `web` | GitHub repo (tu fork) | Rails server |
| `worker` | GitHub repo (tu fork) | Sidekiq background jobs |
| `Postgres` | Plugin Railway | Base de datos |
| `Redis` | Plugin Railway | Caché + Sidekiq |

> **Importante**: `web` y `worker` apuntan al **mismo repo**, se diferencian por sus variables de entorno.

---

## 5. Configurar servicios

### 5.1. Servicio `web`

- **Source**: Deploy from GitHub repo → `TU_USUARIO/chatwoot` → rama `develop`
- **Root directory**: dejar vacío
- **Build**: usa `railway.json` (DOCKERFILE)
- **Start command**: automático (usa el `CMD` del Dockerfile)
- **Puerto**: 3000

Railway asigna un dominio automático como `https://web-production-xxxx.up.railway.app`.

### 5.2. Servicio `worker`

- **Source**: mismo repo, misma rama
- **Build**: mismo Dockerfile
- **Start command**: `bundle exec sidekiq -C config/sidekiq.yml`

> El worker usa la MISMA imagen pero arranca Sidekiq en vez de Rails.

---

## 6. Variables de entorno

### 6.1. Compartidas (web + worker)

| Variable | Valor | Obligatoria |
|---|---|---|
| `RAILS_ENV` | `production` | ✅ |
| `NODE_ENV` | `production` | ✅ |
| `INSTALLATION_ENV` | `docker` | ✅ |
| `SECRET_KEY_BASE` | `openssl rand -hex 64` | ✅ |
| `FRONTEND_URL` | `https://web-production-xxxx.up.railway.app` | ✅ |
| `RAILS_SERVE_STATIC_FILES` | `true` | ✅ |
| `LOG_LEVEL` | `info` | ✅ |
| `ENABLE_ACCOUNT_SIGNUP` | `false` (solo invites) | recomendado |
| `DEFAULT_LOCALE` | `es` | recomendado |
| `DATABASE_URL` | *(inyectada por Railway)* | ✅ |
| `REDIS_URL` | *(inyectada por Railway)* | ✅ |

### 6.2. WhatsApp (opcional, post-deploy)

| Variable | Propósito |
|---|---|
| `WHATSAPP_APP_ID` | ID de la Meta App |
| `WHATSAPP_APP_SECRET` | App Secret de Meta |
| `WHATSAPP_CONFIGURATION_ID` | Configuration ID de Embedded Signup |

### 6.3. Generar SECRET_KEY_BASE

```bash
# Generar una clave segura de 64 bytes en hex
openssl rand -hex 64
```

---

## 7. Levantar Chatwoot por primera vez

### 7.1. Push inicial

El primer push a `develop` dispara el build en Railway.

```bash
git push origin develop
```

### 7.2. Monitorear el build

```bash
railway logs --service web
railway status
```

### 7.3. Migraciones de base de datos

Railway **NO corre las migraciones automáticamente**. Hay que hacerlo a mano.

**Opción A**: Usar Railway Shell (recomendado)

```bash
railway shell --service web
```

Dentro del shell:

```bash
bundle exec rails db:migrate
exit
```

**Opción B**: Forzar migraciones desde un deploy script (no recomendado — la primera vez necesita verificación manual)

### 7.4. Verificar que funciona

```bash
curl -sS https://web-production-xxxx.up.railway.app/
```

Deberías recibir el HTML de la página de login de Chatwoot (no un 502 ni un error JSON).

### 7.5. Crear cuenta Super Admin

1. Abrir `https://web-production-xxxx.up.railway.app` en el navegador
2. Llenar: email, nombre de empresa, contraseña
3. Click en **Create account**
4. Seleccionar rol → **Founder/CEO**
5. Click en **Continue to Dashboard**

---

## 8. Problema conocido: migrations rotas

### 8.1. Síntoma

La migración `20250109065909_add_unique_index_on_taggings.rb` falla porque depende de Redis, pero Redis aún no está disponible durante `db:migrate`.

### 8.2. Solución

Verificar qué migrations fallaron:

```bash
railway shell --service web
```

```bash
bundle exec rails db:migrate:status | grep down
```

Marcar la migration problemática como completada manualmente:

```sql
INSERT INTO schema_migrations (version) VALUES ('20250109065909');
```

Luego correr las migrations restantes:

```bash
bundle exec rails db:migrate
```

### 8.3. Prevención

En versiones futuras de Chatwoot este bug puede estar corregido.  
Siempre verificar `db:migrate:status` después de un upgrade.

---

## 9. Configurar WhatsApp Embedded Signup

### 9.1. Requisitos

- Cuenta de **Meta for Developers**
- **Meta Business Account** verificada
- Dominio **HTTPS fijo** (Railway provee uno)

### 9.2. Embedded Signup (recomendado)

Embedded Signup permite que **tus clientes** conecten WhatsApp con un clic en Facebook Login + verificación SMS. Ellos no necesitan manejar APIs de Meta.

Flujo del lado de Chatwoot:
1. El agente selecciona **Add Inbox → WhatsApp**
2. Aparecen dos opciones:
   - **Connect with Meta** (Embedded Signup)
   - **WhatsApp Cloud API** (manual, con token permanente)
3. El cliente hace click en "Connect with Meta", se autentica con Facebook y verifica su número por SMS
4. Chatwoot recibe el webhook automáticamente

### 9.3. Configurar Meta App

1. Ir a [developers.facebook.com](https://developers.facebook.com)
2. Crear una **App** de tipo **Business**
3. Agregar producto **WhatsApp**
4. Configurar **Webhook**: apuntar a `https://web-production-xxxx.up.railway.app/webhooks/whatsapp`
5. Configurar **Embedded Signup**:
   - Obtener `WHATSAPP_APP_ID` (App ID)
   - Obtener `WHATSAPP_APP_SECRET` (App Secret)
   - Obtener `WHATSAPP_CONFIGURATION_ID`

### 9.4. Agregar variables a Railway

```bash
railway variables set WHATSAPP_APP_ID=tu_app_id
railway variables set WHATSAPP_APP_SECRET=tu_app_secret
railway variables set WHATSAPP_CONFIGURATION_ID=tu_config_id
```

---

## 10. Conectar canales adicionales

### 10.1. Instagram / Facebook Messenger

Ambos usan la API de Meta Graph:

1. Ir a **Settings → Inboxes → Add Inbox**
2. Seleccionar **Facebook** o **Instagram**
3. Conectar con Facebook Login (necesitas una Facebook Page vinculada)
4. Chatwoot configura los webhooks automáticamente

### 10.2. TikTok

Chatwoot tiene soporte nativo para TikTok Business API:

1. Ir a **Settings → Inboxes → Add Inbox**
2. Seleccionar **TikTok**
3. Ingresar `access_token` y `refresh_token` de TikTok Business

> **Nota**: El botón de TikTok puede no aparecer en la UI si no está habilitado en el código.  
> Si no aparece, se puede habilitar desde el panel Super Admin o modificando la UI en `custom/`.

### 10.3. Telegram

1. Ir a **Settings → Inboxes → Add Inbox**
2. Seleccionar **Telegram**
3. Crear un bot con [@BotFather](https://t.me/BotFather)
4. Ingresar el token del bot

---

## 11. Mantenimiento y upgrades

### 11.1. Actualizar desde upstream

```bash
git fetch upstream
git merge upstream/develop
# Resolver conflictos (solo en custom/ o Dockerfile)
git push origin develop
```

Railway redeployea automáticamente al hacer push.

### 11.2. Correr migrations después de un upgrade

```bash
railway shell --service web
bundle exec rails db:migrate
```

### 11.3. Regla de oro

> **NO modifiques archivos fuera de `custom/`**.  
> Si necesitas cambiar algo del core, extiéndelo desde `custom/` usando `prepend_mod_with` o parches con `Custom::Namespace`.  
> Esto permite hacer merge del upstream sin conflictos.

---

## 12. Resolución de problemas

### 12.1. El contenedor no arranca (502 Bad Gateway)

**Posible causa**: El entrypoint `rails.sh` se cuelga con `pg_isready`.

**Solución**: Asegúrate de que el Dockerfile **no tenga ENTRYPOINT**. Railway usa `DATABASE_URL` directamente, no necesita `pg_isready`.

```dockerfile
# ❌ No hacer:
ENTRYPOINT ["docker/entrypoints/rails.sh"]

# ✅ Hacer:
# (no poner ENTRYPOINT, solo CMD)
CMD ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
```

### 12.2. Base de datos vacía (no responde)

**Posible causa**: Faltan migraciones.

**Solución**:

```bash
railway shell --service web
bundle exec rails db:migrate:status
bundle exec rails db:migrate
```

### 12.3. El worker no procesa jobs

Verificar que el comando del worker sea:

```
bundle exec sidekiq -C config/sidekiq.yml
```

Y que tenga las mismas variables de entorno que `web`.

### 12.4. Error "Redis queue missing" en migrations

**Solución**: Marcar manualmente la migration problemática y correr las demás (ver [sección 8](#8-problema-conocido-migrations-rotas)).

### 12.5. Error de conexión a PostgreSQL

Verificar que `DATABASE_URL` esté presente (Railway la inyecta automáticamente en los servicios que tienen PostgreSQL vinculado).

```bash
railway variables get DATABASE_URL --service web
```

### 12.6. Login no aparece

Si la URL devuelve JSON de error en vez del HTML de login:

1. Verificar que las migraciones se corrieron
2. Verificar que `RAILS_SERVE_STATIC_FILES=true`
3. Verificar los logs: `railway logs --service web`

---

## Apéndice A: Comandos Railway útiles

```bash
# Ver todos los proyectos
railway list

# Vincular un proyecto local
railway link --project NOMBRE

# Ver logs de un servicio
railway logs --service web

# Abrir shell en el contenedor
railway shell --service web

# Ver deployments
railway deployment list --service web

# Ver variables de entorno
railway variables list

# Establecer variables
railway variables set CLAVE=VALOR

# Abrir URL del proyecto en el navegador
railway open
```

## Apéndice B: Prueba local con Docker

Para probar cambios localmente antes de subir a Railway:

```bash
# Construir la imagen
docker build -t chatwoot-local .

# Opcional: levantar Postgres y Redis
docker run -d --name chatwoot-pg -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=chatwoot -p 5432:5432 postgres:16
docker run -d --name chatwoot-redis -p 6379:6379 redis:alpine

# Correr Chatwoot
docker run --rm \
  -e DATABASE_URL="postgres://postgres:postgres@host.docker.internal:5432/chatwoot" \
  -e REDIS_URL="redis://host.docker.internal:6379" \
  -e SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  -e RAILS_ENV=production \
  -e RAILS_SERVE_STATIC_FILES=true \
  -e INSTALLATION_ENV=docker \
  -p 3000:3000 \
  chatwoot-local
```

> Nota: `host.docker.internal` solo funciona en macOS. En Linux usar `--network host` o la IP del gateway de Docker.

## Apéndice C: Stack técnico de Chatwoot

| Componente | Tecnología |
|---|---|
| Backend | Ruby on Rails 7.1 |
| Frontend | Vue 3 (Composition API) |
| Base de datos | PostgreSQL + pgvector |
| Cache/Queue | Redis + Sidekiq |
| Build frontend | Vite |
| Contenerización | Docker |
| Hosting recomendado | Railway (Docker) |
