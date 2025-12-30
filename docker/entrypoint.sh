#!/bin/sh
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "${GREEN}🚀 Starting Diagpro Laravel Application...${NC}"

# Wait for database to be ready
echo "${YELLOW}⏳ Waiting for database connection...${NC}"
MAX_TRIES=30
TRIES=0
until php -r "new PDO('mysql:host=${DB_HOST:-mysql};port=${DB_PORT:-3306}', '${DB_USERNAME:-diagpro}', '${DB_PASSWORD}');" 2>/dev/null; do
    TRIES=$((TRIES + 1))
    if [ $TRIES -ge $MAX_TRIES ]; then
        echo "${RED}❌ Database connection timeout after $MAX_TRIES attempts${NC}"
        echo "${YELLOW}Trying to continue anyway...${NC}"
        break
    fi
    echo "${YELLOW}⏳ Database not ready, waiting 5 seconds... (attempt $TRIES/$MAX_TRIES)${NC}"
    sleep 5
done
echo "${GREEN}✅ Database connection established${NC}"

# Wait for Redis to be ready
echo "${YELLOW}⏳ Waiting for Redis connection...${NC}"
TRIES=0
until php -r "new Redis()->connect('${REDIS_HOST:-redis}', ${REDIS_PORT:-6379});" 2>/dev/null; do
    TRIES=$((TRIES + 1))
    if [ $TRIES -ge $MAX_TRIES ]; then
        echo "${RED}❌ Redis connection timeout after $MAX_TRIES attempts${NC}"
        echo "${YELLOW}Trying to continue anyway...${NC}"
        break
    fi
    echo "${YELLOW}⏳ Redis not ready, waiting 3 seconds... (attempt $TRIES/$MAX_TRIES)${NC}"
    sleep 3
done
echo "${GREEN}✅ Redis connection established${NC}"

# Set proper permissions
echo "${YELLOW}🔧 Setting up permissions...${NC}"
chown -R nginx:nginx /var/www 2>/dev/null || true
chmod -R 755 /var/www
chmod -R 775 /var/www/storage
chmod -R 775 /var/www/bootstrap/cache

# Create required directories
mkdir -p /var/lib/php83/sessions
chown -R nginx:nginx /var/lib/php83/sessions
chmod 755 /var/lib/php83/sessions

# Create log directories
mkdir -p /var/log/supervisor
mkdir -p /var/log/mysql
touch /var/log/php-errors.log
touch /var/log/php-fpm.log
touch /var/log/php-fpm-slow.log
chown nginx:nginx /var/log/php-*.log

# Laravel setup
echo "${YELLOW}🔧 Setting up Laravel...${NC}"

# Generate app key if not exists
if [ -z "$APP_KEY" ]; then
    echo "${YELLOW}🔑 Generating application key...${NC}"
    php artisan key:generate --force
fi

# Clear and cache config
echo "${YELLOW}⚡ Optimizing Laravel...${NC}"
php artisan config:clear
php artisan config:cache
php artisan route:clear
php artisan route:cache
php artisan view:clear
php artisan view:cache

# Run migrations
echo "${YELLOW}🗄️ Running database migrations...${NC}"
php artisan migrate --force

# Seed database if needed
if [ "$DB_SEED" = "true" ]; then
    echo "${YELLOW}🌱 Seeding database...${NC}"
    php artisan db:seed --force
fi

# Create storage link
echo "${YELLOW}🔗 Creating storage link...${NC}"
php artisan storage:link || true

# Clear all caches
echo "${YELLOW}🧹 Clearing caches...${NC}"
php artisan cache:clear || true
php artisan queue:clear || true

# Start queue worker in background if not in worker container
if [ "$CONTAINER_ROLE" != "worker" ] && [ "$CONTAINER_ROLE" != "scheduler" ]; then
    echo "${GREEN}✅ Laravel application ready!${NC}"
    echo "${GREEN}🌐 Starting web server...${NC}"
    
    # Start supervisor
    exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
else
    # This is a worker or scheduler container
    if [ "$CONTAINER_ROLE" = "worker" ]; then
        echo "${GREEN}👷 Starting Laravel Queue Worker...${NC}"
        exec php artisan queue:work --verbose --tries=3 --timeout=90 --memory=512
    elif [ "$CONTAINER_ROLE" = "scheduler" ]; then
        echo "${GREEN}⏰ Starting Laravel Scheduler...${NC}"
        # Run scheduler every minute
        while true; do
            php artisan schedule:run --verbose --no-interaction &
            sleep 60
        done
    fi
fi