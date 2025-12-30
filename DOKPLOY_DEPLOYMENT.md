# Deployment su Dokploy - Diagpro

Questa guida spiega come deployare l'applicazione Diagpro su Dokploy usando Docker Compose.

## File da Usare

**Per Dokploy usa: `docker-compose.dokploy.yml`**

## Architettura dei Servizi

| Servizio | Immagine | Porta | Descrizione |
|----------|----------|-------|-------------|
| **app** | Custom (Dockerfile) | 80 | Laravel + Nginx + PHP-FPM |
| **mysql** | mysql:8.0 | 3306 | Database MySQL |
| **redis** | redis:7-alpine | 6379 | Cache, Session |

> **Nota**: Queue worker e scheduler NON sono necessari perché il progetto non usa job in coda né task schedulati.

## Sincronizzazione Database

Il database viene sincronizzato automaticamente tramite:

1. **Migrazioni automatiche**: L'entrypoint esegue `php artisan migrate --force` ad ogni avvio
2. **Seeding opzionale**: Impostare `DB_SEED=true` per eseguire i seeder al primo avvio
3. **Volume persistente**: I dati MySQL sono salvati nel volume `mysql_data`

## Pre-requisiti

1. Server con Dokploy installato
2. Dominio configurato (opzionale ma consigliato)
3. Almeno 2GB RAM disponibili

## Passi per il Deployment

### 1. Preparare le Variabili d'Ambiente

Crea un file `.env` nella root del progetto basandoti su `.env.dokploy`:

```bash
cp .env.dokploy .env
```

**Variabili OBBLIGATORIE da configurare:**

```env
APP_KEY=                          # Generato automaticamente se vuoto
APP_URL=https://tuo-dominio.com
DB_PASSWORD=password_sicura_db
DB_ROOT_PASSWORD=password_root_sicura
REDIS_PASSWORD=password_sicura_redis

MAIL_HOST=smtp.tuoprovider.com
MAIL_USERNAME=utente@email.com
MAIL_PASSWORD=password_email
MAIL_FROM_ADDRESS=noreply@tuo-dominio.com

FILAMENT_DOMAIN=tuo-dominio.com
```

> **⚠️ SICUREZZA**: Usa password complesse e uniche per produzione

### 2. Configurazione su Dokploy

#### Opzione A: Deploy da Git Repository

1. Vai su Dokploy → **Projects** → **Create Project**
2. Seleziona **Compose**
3. Collega il tuo repository Git
4. Seleziona il file **`docker-compose.dokploy.yml`**
5. Configura le variabili d'ambiente nella sezione **Environment**

#### Opzione B: Deploy manuale

1. Carica i file sul server
2. In Dokploy, crea un nuovo progetto **Compose**
3. Seleziona **`docker-compose.dokploy.yml`** come compose file
4. Configura le variabili d'ambiente

### 3. Variabili d'Ambiente in Dokploy

Nella sezione **Environment Variables** di Dokploy, aggiungi:

```
APP_KEY=base64:GENERA_UNA_CHIAVE_SICURA
APP_URL=https://tuo-dominio.com
DB_PASSWORD=TUA_PASSWORD_SICURA
DB_ROOT_PASSWORD=TUA_PASSWORD_ROOT_SICURA
REDIS_PASSWORD=TUA_PASSWORD_REDIS_SICURA
DB_SEED=false
```

> **⚠️ IMPORTANTE**: Usa password complesse e uniche per produzione

### 4. Configurazione Domini

In Dokploy → **Domains**:

1. Aggiungi il tuo dominio
2. Punta al servizio `app` porta `80`
3. Abilita HTTPS con Let's Encrypt

### 5. Deploy

Clicca su **Deploy** in Dokploy. Il sistema:

1. Builda le immagini Docker
2. Avvia MySQL e Redis
3. Attende che i servizi siano pronti
4. Esegue le migrazioni automaticamente
5. Avvia l'applicazione Laravel

## Verifica del Deployment

### Health Check

Visita `https://tuo-dominio.com/health` per verificare lo stato:

```json
{
  "status": "healthy",
  "timestamp": "2024-12-30T20:00:00+00:00",
  "services": {
    "database": "ok",
    "redis": "ok"
  }
}
```

### Pannello Admin Filament

Accedi a `https://tuo-dominio.com/admin`

## Comandi Utili

### Accedere al container app

```bash
docker exec -it diagpro-app sh
```

### Eseguire comandi Artisan

```bash
docker exec -it diagpro-app php artisan migrate:status
docker exec -it diagpro-app php artisan cache:clear
docker exec -it diagpro-app php artisan queue:restart
```

### Visualizzare i log

```bash
docker logs diagpro-app
docker logs diagpro-mysql
docker logs diagpro-redis
```

### Backup Database

```bash
docker exec diagpro-mysql mysqldump -u diagpro -p diagpro > backup.sql
```

### Restore Database

```bash
docker exec -i diagpro-mysql mysql -u diagpro -p diagpro < backup.sql
```

## Troubleshooting

### L'app non si avvia

1. Controlla i log: `docker logs diagpro-app`
2. Verifica che MySQL sia pronto: `docker logs diagpro-mysql`
3. Verifica le variabili d'ambiente

### Errore di connessione al database

1. Verifica che `DB_HOST=mysql` (nome del servizio)
2. Controlla `DB_PASSWORD` sia uguale a `MYSQL_PASSWORD`
3. Attendi che MySQL sia completamente avviato (può richiedere 30-60 secondi)

### Errore Redis

1. Verifica che `REDIS_HOST=redis`
2. Controlla che `REDIS_PASSWORD` corrisponda a quella in `redis.conf`

### Permessi storage

```bash
docker exec -it diagpro-app chmod -R 775 /var/www/storage
docker exec -it diagpro-app chmod -R 775 /var/www/bootstrap/cache
```

## Backup Automatici

Configura un cron job sul server host:

```bash
0 2 * * * docker exec diagpro-mysql mysqldump -u diagpro -pPASSWORD diagpro | gzip > /backups/diagpro_$(date +\%Y\%m\%d).sql.gz
```

## Aggiornamenti

Per aggiornare l'applicazione:

1. Push delle modifiche al repository Git
2. In Dokploy, clicca **Redeploy**
3. Le migrazioni vengono eseguite automaticamente

## Volumi Persistenti

| Volume | Path nel Container | Descrizione |
|--------|-------------------|-------------|
| `mysql_data` | `/var/lib/mysql` | Dati MySQL |
| `redis_data` | `/data` | Dati Redis |
| `storage_data` | `/var/www/storage` | File Laravel |

**⚠️ IMPORTANTE**: Non eliminare questi volumi o perderai tutti i dati!
