FROM mlocati/php-extension-installer:latest AS installer
FROM php:8.2-fpm

COPY --from=installer /usr/bin/install-php-extensions /usr/bin/

RUN apt-get update && apt-get install -y \
    git curl libpng-dev libonig-dev libxml2-dev \
    libzip-dev libicu-dev zip unzip nodejs npm \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# install-php-extensions downloads pre-built binaries — no compilation
RUN install-php-extensions grpc protobuf intl gd zip bcmath pdo_mysql mbstring exif pcntl

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

COPY composer.json composer.lock* ./
RUN composer install --no-scripts --no-autoloader --prefer-dist

COPY . .
RUN composer dump-autoload --optimize

RUN chown -R www-data:www-data /var/www \
    && chmod -R 755 /var/www/storage \
    && chmod -R 755 /var/www/bootstrap/cache

EXPOSE 9000
CMD ["php-fpm"]