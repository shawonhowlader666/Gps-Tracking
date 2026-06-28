FROM richarvey/nginx-php-fpm:3.1.6

# Set Nginx web root directory to Laravel public folder
ENV WEBROOT /var/www/html/public

# Copy application source code
COPY . .

# Run Composer installation automatically during container boot/build
ENV COMPOSER_AS_ROOT 1
ENV SKIP_COMPOSER 0

# Set write permissions for Laravel storage and cache
RUN chmod -R 777 storage bootstrap/cache
