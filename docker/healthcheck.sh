#!/bin/sh
# Healthy = php-fpm master answers on its FastCGI socket AND Moodle is readable.
set -eu

PORT="${MOODLE_FPM_PORT:-9000}"

# 1. php-fpm must be listening. A dead master is the most common failure.
PORT="$PORT" php -r '
    $h = @fsockopen("127.0.0.1", (int) getenv("PORT"), $e, $s, 2);
    if ($h) { fclose($h); exit(0); }
    exit(1);
' || exit 1

# 2. The code tree must be present and readable — catches a broken mount/copy.
[ -r /var/www/moodle/public/index.php ] || exit 1
[ -r /var/www/moodle/public/lib/setup.php ] || exit 1

# 3. dataroot must be writable, otherwise every upload and session breaks.
DATAROOT="${MOODLE_DATAROOT:-/var/www/moodledata}"
[ -d "$DATAROOT" ] || exit 1
[ -w "$DATAROOT" ] || exit 1

exit 0