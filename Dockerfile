# Multi-stage Dockerfile per Diagpro Laravel App
# Stage 1: Build dependencies
FROM php:8.3-fpm-alpine AS builder

# Install system dependencies
RUN apk add --no-cache \
    git \
    curl \
    libpng-dev \
    libxml2-dev \
    zip \
    unzip \
    nodejs \
    npm \
    mysql-client \
    icu-dev \
    zlib-dev \
    libzip-dev \
    oniguruma-dev

# Install PHP extensions
RUN docker-php-ext-install pdo pdo_mysql mbstring exif pcntl bcmath gd intl zip

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www

# Copy composer files
COPY composer.json composer.lock ./

# Install PHP dependencies
RUN composer install --no-dev --optimize-autoloader --no-scripts

# Copy package.json and install Node dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY . .

# Build frontend assets
RUN npm run build

# Run composer scripts
RUN composer run-script post-autoload-dump

# Stage 2: Production image
FROM nginx:alpine AS production

# Install PHP-FPM and required extensions
RUN apk add --no-cache \
    php83 \
    php83-fpm \
    php83-pdo \
    php83-pdo_mysql \
    php83-mbstring \
    php83-exif \
    php83-pcntl \
    php83-bcmath \
    php83-gd \
    php83-xml \
    php83-zip \
    php83-curl \
    php83-fileinfo \
    php83-tokenizer \
    php83-session \
    php83-ctype \
    php83-json \
    php83-openssl \
    php83-pecl-redis \
    php83-intl \
    supervisor \
    curl \
    mysql-client

# Create symlink for php
RUN rm -f /usr/bin/php && ln -s /usr/bin/php83 /usr/bin/php

# Create a non-root user and group
RUN addgroup -g 1001 diagpro && \
    adduser -u 1001 -G diagpro -s /bin/sh -D diagpro

# Copy application from builder stage
COPY --from=builder /var/www /var/www

# Set working directory
WORKDIR /var/www

# Copy Nginx configuration
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf

# Copy PHP-FPM configuration
COPY docker/php/php-fpm.conf /etc/php83/php-fpm.conf
COPY docker/php/www.conf /etc/php83/php-fpm.d/www.conf

# Copy Supervisor configuration
COPY docker/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy entrypoint script
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set proper permissions
RUN chown -R diagpro:diagpro /var/www \
    && chmod -R 755 /var/www/storage \
    && chmod -R 755 /var/www/bootstrap/cache

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Start supervisor
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]