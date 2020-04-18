#!/bin/sh

docker run --rm   --volume="$PWD:/srv/jekyll" --volume="$PWD/vendor/bundle:/usr/local/bundle" --env JEKYLL_ENV=development -p 8080:4000 jekyll/jekyll jekyll serve --config _config.yml,_config-dev.yml
