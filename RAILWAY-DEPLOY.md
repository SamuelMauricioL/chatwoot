# 🚂 Manual de Deploy de Chatwoot en Railway

> **Versión**: 2.0
> **Stack**: Ruby on Rails 7.1 + Vue 3 + PostgreSQL + Redis + Sidekiq
> **URL ejemplo**: `https://web-production-xxxx.up.railway.app`

---

## Índice

1. [Requisitos previos](#1-requisitos-previos)
2. [Fork del repositorio](#2-fork-del-repositorio)
3. [Estructura de personalización `custom/`](#3-estructura-de-personalización-custom)
4. [Crear el proyecto en Railway](#4-crear-el-proyecto-en-railway)
5. [Configurar servicios](#5-configurar-servicios)
6. [Variables de entorno](#6-variables-de-entorno)
7. [Archivos requeridos del proyecto](#7-archivos-requeridos-del-proyecto)
8. [Push y primer build](#8-push-y-primer-build)
9. [Migraciones de base de datos](#9-migraciones-de-base-de-datos)
10. [Verificar que funciona](#10-verificar-que-funciona)
11. [Crear cuenta Super Admin](#11-crear-cuenta-super-admin)
12. [Configurar WhatsApp Embedded Signup](#12-configurar-whatsapp-embedded-signup)
13. [Conectar canales adicionales](#13-conectar-canales-adicionales)
14. [Mantenimiento y upgrades](#14-mantenimiento-y-upgrades)
15. [Resolución de problemas](#15-resolución-de-problemas)
16. [Bugs conocidos](#16-bugs-conocidos)

---

## 1. Requisitos previos

- Cuenta en **GitHub**
- Cuenta en **Railway** (railway.app) — plan Hobby o superior
- **Railway CLI** (`brew install railway`)
- **Docker Desktop** (para pruebas locales)
- Cuenta de **Meta Developer** (para WhatsApp/Instagram/Facebook)

---

## 2. Fork del repositorio

Hacer fork de https://github.com/chatwoot/chatwoot a tu cuenta de GitHub:

```bash
git clone https://github.com/TU_USUARIO/chatwoot.git
cd chatwoot
git remote add upstream https://github.com/chatwoot/chatwoot.git
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
mkdir -p custom/config
```

### 3.2. Crear `custom/config/cable.yml`

**⚠️ OBLIGATORIO** — La imagen base de Chatwoot usa `.presence` en `config/cable.yml`, un método de ActiveSupport que NO está disponible al momento de cargar este archivo en Rails 7.1 + Ruby 3.4. Causa crash inmediato al bootear.

Crear `custom/config/cable.yml`:

```yaml
default: &default
  adapter: redis
  url: <%= ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379') %>
  channel_prefix: <%= "chatwoot_#{Rails.env}_action_cable" %>

development:
  <<: *default

test:
  adapter: test
  channel_prefix: <%= "chatwoot_#{Rails.env}_action_cable" %>

staging:
  <<: *default

production:
  <<: *default
```

> Las líneas `password` y `ssl_params` fueron eliminadas porque usaban `.presence` y `Chatwoot.redis_ssl_verify_mode` respectivamente, y ambos fallan en la fase temprana de carga de config.

### 3.3. Configurar `config/application.rb`

Agregar al final del bloque `class Application < Rails::Application`:

```ruby
# ─── Custom Extensions ──────────────────────────────────────────────
if Rails.root.join('custom').exist?
  config.eager_load_paths << Rails.root.join('custom/lib')
  config.eager_load_paths += Dir["#{Rails.root}/custom/app/**"]
  config.paths['app/views'].unshift('custom/app/views')

  custom_initializers = Rails.root.join('custom/config/initializers')
  Dir[custom_initializers.join('**/*.rb')].each { |f| require f } if custom_initializers.exist?
end
```

### 3.4. Dockerfile

El `chatwoot/chatwoot:develop` viene con `CMD ["irb"]`. Además, **NO** debe usar `ENTRYPOINT` porque el entrypoint `docker/entrypoints/rails.sh` se cuelga con `pg_isready` en Railway.

Crear `Dockerfile` en la raíz del repo:

```dockerfile
ARG CW_TAG=develop
FROM chatwoot/chatwoot:${CW_TAG}
COPY custom/ /app/custom/
COPY config/application.rb /app/config/application.rb
# ⚠️ Fix: cable.yml usa .presence que crashea en Rails 7.1 + Ruby 3.4
COPY custom/config/cable.yml /app/config/cable.yml
# Railway: NO usar entrypoint (pg_isready se cuelga)
CMD ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
```

### 3.5. railway.json

**⚠️ OBLIGATORIO** — Railway auto-detecta un `startCommand` que usa `$PORT`. Si esa variable no está seteada, Rails no arranca. Debemos fijarlo explícitamente.

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
    "restartPolicyMaxRetries": 10,
    "startCommand": "bundle exec rails s -p 3000 -b 0.0.0.0"
  }
}
```

### 3.6. Commit inicial

```bash
git add custom/ Dockerfile railway.json config/application.rb
git commit -m "feat: add Railway deployment setup with custom extensions"
git push origin develop
```

---

## 4. Crear el proyecto en Railway

### 4.1. Login

```bash
railway login
```

### 4.2. Crear proyecto

```bash
railway init
```

Seleccionar:
- **Workspace**: tu workspace personal
- **Nombre**: `chatwoot` (o el que prefieras)

Esto crea el proyecto vacío.

### 4.3. Vincular proyecto

```bash
railway link --project NOMBRE_DEL_PROYECTO
```

---

## 5. Configurar servicios

Crear **4 servicios** dentro del proyecto Railway:

### Servicio `web` (Rails server)

- **Source**: Deploy from GitHub repo → `TU_USUARIO/chatwoot` → rama `develop`
- **Build**: usa `railway.json` (DOCKERFILE)
- **Start command**: lo define `railway.json` → `bundle exec rails s -p 3000 -b 0.0.0.0`
- **Puerto**: 3000 (por el EXPOSE de la imagen)

Railway asigna un dominio automático tipo `https://web-production-xxxx.up.railway.app`.

### Servicio `worker` (Sidekiq)

- **Source**: mismo repo, misma rama
- **Start command**: `bundle exec sidekiq -C config/sidekiq.yml`

> Usa la MISMA imagen Docker pero arranca Sidekiq en vez de Rails.

### Servicio `Postgres`

- Usar el plugin de Railway (PostgreSQL)

### Servicio `Redis`

- Usar el plugin de Railway (Redis)

---

## 6. Variables de entorno

### 6.1. Compartidas (web + worker)

- `RAILS_ENV` → `production`
- `NODE_ENV` → `production`
- `INSTALLATION_ENV` → `docker`
- `SECRET_KEY_BASE` → generar con `openssl rand -hex 64`
- `FRONTEND_URL` → `https://web-production-xxxx.up.railway.app`
- `RAILS_SERVE_STATIC_FILES` → `true`
- `LOG_LEVEL` → `info`
- `ENABLE_ACCOUNT_SIGNUP` → `false` (recomendado)
- `DEFAULT_LOCALE` → `es` (recomendado)
- `PORT` → `3000` — **OBLIGATORIO**, Railway necesita saber el puerto
- `DATABASE_URL` → *(inyectada por Railway al vincular Postgres)*
- `REDIS_URL` → *(inyectada por Railway al vincular Redis)*

### 6.2. WhatsApp (post-deploy, opcional)

- `WHATSAPP_APP_ID` — ID de la Meta App
- `WHATSAPP_APP_SECRET` — App Secret de Meta
- `WHATSAPP_CONFIGURATION_ID` — Configuration ID de Embedded Signup

---

## 7. Archivos requeridos del proyecto

Resumen de todos los archivos que deben existir en el fork para que Railway funcione:

| Archivo | Propósito |
|---|---|
| `Dockerfile` | `FROM chatwoot/chatwoot:develop` (build rápido, 7 líneas) |
| `railway.json` | Build DOCKERFILE + startCommand explícito |
| `.ruby-version` | `3.4.4` (NO 3.3.x — el fix real fue el coder) |
| `Gemfile` | `ruby '3.4.4'` |
| `config/application.rb` | Carga de `custom/` paths + `lib/` en eager_load |
| `config/initializers/clear_stale_cache.rb` | Limpia cache corrupto de Redis al bootear |
| `lib/custom_coders/jsonb_yaml_coder.rb` | Fix: coder jsonb que maneja YAML + Hash nativo |
| `custom/config/cable.yml` | Fix: sin `.presence` para Rails 7.1 |
| `custom/.gitkeep` | Para que git trackee el directorio |
| `custom/README.md` | Documentación de la estructura custom |

---

## 8. Push y primer build

```bash
git push origin develop
```

Railway detecta el push y comienza el build automáticamente.

Monitorear:

```bash
railway logs --build --service web
railway status
```

El build típicamente toma 1-3 minutos (usa caché Docker).  
El deploy toma otros 30-60 segundos.

---

## 9. Migraciones de base de datos

Railway **NO corre migraciones automáticamente**. Hay que hacerlo a mano.

```bash
railway shell --service web
bundle exec rails db:migrate
exit
```

Si alguna migration falla por dependencia de Redis (bug conocido en v4.16.1), ver [Bugs conocidos](#16-bugs-conocidos).

---

## 10. Verificar que funciona

```bash
curl -sS https://web-production-xxxx.up.railway.app/ | head -20
```

Deberías ver HTML de la página de login de Chatwoot (con `<title>Chatwoot</title>`).

Los logs deben mostrar:

```
=> Booting Puma
=> Rails 7.1.5.2 application starting in production
Puma starting in single mode...
* Listening on http://0.0.0.0:3000
```

---

## 11. Crear cuenta Super Admin

1. Abrir `https://web-production-xxxx.up.railway.app` en el navegador
2. Llenar: **email**, **nombre de empresa**, **contraseña**
3. Click en **Create account**
4. Seleccionar **rol** → **Founder/CEO**
5. Click en **Continue to Dashboard**

---

## 12. Configurar WhatsApp Embedded Signup

Embedded Signup permite que **tus clientes** conecten WhatsApp con un clic (Facebook Login + SMS), sin manejar APIs de Meta.

### Requisitos

- Cuenta de **Meta for Developers**
- **Meta Business Account** verificada
- Dominio **HTTPS fijo** (Railway provee uno)

### Pasos

1. Ir a [developers.facebook.com](https://developers.facebook.com)
2. Crear una **App Business**
3. Agregar producto **WhatsApp**
4. Configurar **Webhook**: apuntar a `https://web-production-xxxx.up.railway.app/webhooks/whatsapp`
5. Obtener:
   - `WHATSAPP_APP_ID` (App ID)
   - `WHATSAPP_APP_SECRET` (App Secret)
   - `WHATSAPP_CONFIGURATION_ID` (Embedded Signup)
6. Agregar a Railway:
   ```bash
   railway variables set WHATSAPP_APP_ID=tu_app_id
   railway variables set WHATSAPP_APP_SECRET=tu_app_secret
   railway variables set WHATSAPP_CONFIGURATION_ID=tu_config_id
   ```

### Flujo del cliente

- Agente selecciona **Add Inbox → WhatsApp**
- Aparecen opciones: **Connect with Meta** (Embedded) o **WhatsApp Cloud API** (manual)
- Cliente hace click en "Connect with Meta", se autentica con Facebook y verifica su número por SMS
- Chatwoot recibe el webhook automáticamente

---

## 13. Conectar canales adicionales

### Instagram / Facebook Messenger

Ambos usan Meta Graph API:

1. **Settings → Inboxes → Add Inbox**
2. Seleccionar **Facebook** o **Instagram**
3. Conectar con Facebook Login (necesitas una Facebook Page)
4. Chatwoot configura los webhooks automáticamente

### TikTok

Chatwoot tiene soporte nativo para TikTok Business API:

1. **Settings → Inboxes → Add Inbox**
2. Seleccionar **TikTok**
3. Ingresar `access_token` y `refresh_token` de TikTok Business

> El botón de TikTok puede no aparecer en la UI si no está habilitado.  
> Se puede habilitar desde Super Admin o modificando la UI en `custom/`.

### Telegram

1. **Settings → Inboxes → Add Inbox**
2. Seleccionar **Telegram**
3. Crear un bot con [@BotFather](https://t.me/BotFather)
4. Ingresar el token del bot

### Email

Soporta IMAP/SMTP. Configurar en Settings → Inboxes → Email.

### SMS

Soporta Twilio. Configurar en Settings → Inboxes → SMS.

### Website Widget

Chatwoot incluye un widget de chat embeddable para sitios web.

---

## 14. Mantenimiento y upgrades

### Actualizar desde upstream

```bash
git fetch upstream
git merge upstream/develop
# Resolver conflictos (solo en custom/ o Dockerfile)
git push origin develop
```

Railway redeployea automáticamente.

### Correr migrations después de un upgrade

```bash
railway shell --service web
bundle exec rails db:migrate
```

### Regla de oro

> **NO modifiques archivos fuera de `custom/`**.  
> Si necesitas cambiar algo del core, extiéndelo desde `custom/` usando `prepend_mod_with` o `Custom::Namespace`.  
> Esto permite hacer merge del upstream sin conflictos.

---

## 15. Resolución de problemas

### 502 Bad Gateway — Rails no arranca

Verificar los logs:

```bash
railway logs --service web
```

**Causa común 1**: `startCommand` incorrecto en Railway. Railway auto-detecta un comando que usa `$PORT`. Si `PORT` no está seteado, Rails falla.  
**Solución**: Asegurarse de que `railway.json` tenga `startCommand` explícito y `PORT=3000` en variables.

**Causa común 2**: El entrypoint `rails.sh` se cuelga con `pg_isready`.  
**Solución**: El Dockerfile **no debe tener ENTRYPOINT**. Solo CMD.

**Causa común 3**: `config/cable.yml` crashea por `.presence`.  
**Solución**: Incluir `custom/config/cable.yml` en el proyecto.

### Logs no muestran "Booting Puma"

Revisar logs completos:

```bash
railway logs --service web
```

Si ves solo warnings iniciales pero no `=> Booting Puma`, el error ocurre durante el boot de Rails. Las causas más probables:

1. `cable.yml` con `.presence` → incluir `custom/config/cable.yml`
2. Redis no accesible → verificar `REDIS_URL` y que Redis esté Online
3. Database no accesible → verificar `DATABASE_URL`

### Worker no procesa jobs

Verificar que el comando del worker sea:

```
bundle exec sidekiq -C config/sidekiq.yml
```

Y que tenga las mismas variables de entorno que `web`.

### Error de conexión a PostgreSQL

```bash
railway variable list --service web --json | grep DATABASE_URL
```

Railway inyecta `DATABASE_URL` automáticamente cuando el servicio Postgres está vinculado.

### Errores 500 en producción

Si hay errores 500 después del login exitoso, verificar:

```bash
railway logs --service web | grep ERROR
```

También verificar que las migrations estén completas:

```bash
railway shell --service web
bundle exec rails db:migrate:status
```

---

## 16. Bugs conocidos

### Bug 1: `config/cable.yml` — `.presence` en nil/string

**Síntoma**: Rails crashea al bootear con `undefined method 'presence' for nil/instance of String`.  
**Causa**: `cable.yml` usa `ENV.fetch('REDIS_PASSWORD', nil).presence` — ActiveSupport no ha cargado sus extensiones de core al momento de evaluar este ERB.  
**Afecta**: Chatwoot v4.16.1 en Ruby 3.4 con Railway.  
**Solución**: Incluir `custom/config/cable.yml` que elimina las líneas problemáticas.

### Bug 2: `docker/entrypoints/rails.sh` — pg_isready se cuelga

**Síntoma**: Contenedor nunca termina de arrancar, logs muestran loop de `pg_isready`.  
**Causa**: El entrypoint usa `pg_isready` con variables extraídas de `DATABASE_URL`. En Railway el parsing falla y el comando se cuelga en loop infinito.  
**Solución**: NO usar ENTRYPOINT en el Dockerfile. Railway maneja dependencias entre servicios.

### Bug 3: Cinema — startCommand auto-detectado con `$PORT`

**Síntoma**: Railway usa `bundle exec rails s -p $PORT -e $RAILS_ENV` como startCommand, pero `$PORT` no está seteado.  
**Causa**: Railway auto-detecta el startCommand y lo persiste en la configuración del servicio, ignorando el CMD del Dockerfile.  
**Solución**: Fijar `startCommand` en `railway.json` y `PORT=3000` en variables de entorno.

### Bug 5: `TypeError (no implicit conversion of Hash into String)` en root `/`

**Síntoma**: Error 500 en la página principal. Logs muestran:

```
TypeError (no implicit conversion of Hash into String):
app/models/installation_config.rb:49:in `value'
lib/global_config.rb:54:in `db_fallback'
```

**Causa raíz**: `serialize :serialized_value, coder: YAML` sobre una columna **jsonb**. Cuando el parser jsonb de PostgreSQL devuelve un Hash nativo, `YAML.safe_load` recibe un Hash donde espera un String, causando `TypeError`.

**Afecta**: Chatwoot v4.16.1 con Ruby 3.4+. También afecta Ruby 3.3 si hay registros almacenados como JSON nativo en vez de YAML string.

**Solución**: Reemplazar `coder: YAML` por un coder personalizado que maneje ambos formatos.

#### Archivos creados/modificados:

**`lib/custom_coders/jsonb_yaml_coder.rb`** — Nuevo coder que maneja:
- **String** → YAML string (formato antiguo, dentro de JSON)
- **Hash** → valor nativo jsonb (formato correcto)

```ruby
module CustomCoders
  class JsonbYamlCoder
    def self.dump(obj)
      obj  # jsonb column maneja la serialización nativamente
    end

    def self.load(payload)
      return {}.with_indifferent_access if payload.nil?

      case payload
      when String
        parsed = YAML.safe_load(payload, permitted_classes: [ActiveSupport::HashWithIndifferentAccess, Symbol]) || {}
        parsed = { value: parsed } unless parsed.is_a?(Hash)
        parsed.with_indifferent_access
      when Hash
        payload.with_indifferent_access
      else
        { value: payload }.with_indifferent_access
      end
    rescue StandardError => e
      Rails.logger.warn "[JsonbYamlCoder] Failed: #{e.message}"
      { value: payload }.with_indifferent_access
    end
  end
end
```

**`app/models/installation_config.rb`** — Cambiar `coder: YAML` → `CustomCoders::JsonbYamlCoder`:

```ruby
# Antes (ROTO):
serialize :serialized_value, coder: YAML, type: ActiveSupport::HashWithIndifferentAccess, default: {}.with_indifferent_access

# Después (FUNCIONA):
serialize :serialized_value, coder: CustomCoders::JsonbYamlCoder, type: ActiveSupport::HashWithIndifferentAccess, default: {}.with_indifferent_access
```

### Bug 6: `ActionView::Template::Error (invalid base64)` — Cache stale de Redis

**Síntoma**: Después de aplicar el fix del Bug 5, el root aún falla con:

```
ActionView::Template::Error (invalid base64):
app/views/layouts/vueapp.html.erb:54
Base64.urlsafe_decode64(@global_config['VAPID_PUBLIC_KEY'])
```

**Causa**: `GlobalConfig` cachea valores en Redis. Durante deploys anteriores con el coder roto, se almacenaron valores corruptos (Hashes serializados incorrectamente) en Redis. Al leer del cache, el nuevo coder nunca se usa — el valor corrupto viene directo de Redis.

**Solución**: Limpiar el cache de Redis al bootear.

**`config/initializers/clear_stale_cache.rb`** — Nuevo initializer:

```ruby
Rails.application.config.after_initialize do
  GlobalConfig.clear_cache
  Rails.logger.info '[clear_stale_cache] Cleared stale GlobalConfig Redis cache'
end
```

> **Nota**: No poner `GlobalConfig.clear_cache` en el `startCommand` de Railway — puede causar 502 porque ejecuta un proceso separado que compite con Puma.

**Para limpiar el cache manualmente si el initializer no se ha deployado aún:**

```bash
railway ssh -s web -- 'bundle exec rails runner "GlobalConfig.clear_cache"'
```

### Bug 7: Deploy fallido en Railway no se recupera solo

**Síntoma**: Railway muestra "Deploy failed" y no despliega los nuevos builds aunque `railway up` se ejecute correctamente.

**Causa**: Railway mantiene el contenedor anterior corriendo (el que tenía el deploy exitoso previo) pero no actualiza a nuevas imágenes hasta que el deploy fallido se resuelva.

**Solución**: Usar `railway redeploy --yes` para forzar un redeploy desde el último commit, o conectar via SSH al container running:

```bash
# Forzar redeploy
railway redeploy --yes

# O conectar al container running y ejecutar fixes manualmente
railway ssh -s web -- 'bundle exec rails runner "comando"'
```

### Bug 8: Ruby 3.4 incompatible con Chatwoot v4.16.1

**Síntoma**: Múltiples errores en producción, incluyendo `TypeError` y warnings de RubyLLM.

**Realidad**: **Ruby 3.4 NO es el problema.** La causa real fue `coder: YAML` en columna jsonb. El error ocurre igual en Ruby 3.3 y 3.4. Usar Ruby 3.4.4 es perfectamente compatible con el `CustomCoders::JsonbYamlCoder`.

**No hace falta downgradear Ruby**. Usar `FROM chatwoot/chatwoot:develop` en el Dockerfile (build rápido, imagen precompilada con Ruby 3.4).

**Síntoma**: `bundle exec rails db:migrate` falla con error de Redis.  
**Causa**: La migración `20250109065909_add_unique_index_on_taggings.rb` (o similar) depende de Redis, que no está disponible durante `db:migrate`.  
**Solución**: Marcar como completada manualmente:

```bash
railway shell --service web
```

```sql
INSERT INTO schema_migrations (version) VALUES ('20250109065909');
```

Luego:

```bash
bundle exec rails db:migrate
```

---

## Apéndice A: Comandos Railway útiles

```bash
# Ver todos los proyectos
railway list

# Vincular proyecto local
railway link --project NOMBRE

# Ver logs de un servicio
railway logs --service web

# Ver build logs
railway logs --build --service web

# Shell en el contenedor
railway shell --service web

# Ver deployments
railway deployment list --service web

# Ver variables
railway variable list --service web --json

# Setear variables
railway variable set CLAVE=VALOR

# Abrir proyecto en navegador
railway open

# Forzar redeploy sin rebuild
railway restart --service web
```

---

## Apéndice B: Prueba local con Docker

```bash
# Construir la imagen local
docker build -t chatwoot-local .

# Postgres y Redis locales
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

> `host.docker.internal` solo funciona en macOS. En Linux usar `--network host`.

---

## Apéndice C: Stack técnico

- **Backend**: Ruby on Rails 7.1
- **Frontend**: Vue 3 (Composition API)
- **Base de datos**: PostgreSQL + pgvector
- **Cache/Queue**: Redis + Sidekiq
- **Build frontend**: Vite
- **Contenerización**: Docker
- **Hosting**: Railway (Docker)
