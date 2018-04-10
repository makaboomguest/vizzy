#Dockerfile
FROM ruby:2.3.7
LABEL maintainer="Scott Bishop - ScottBishop70@gmail.com"

# Install tools & libs
RUN apt-get update
RUN apt-get install -y build-essential checkinstall libx11-dev libxext-dev zlib1g-dev libpng12-dev libjpeg-dev libfreetype6-dev libxml2-dev nodejs libnss3

RUN apt-get install -y imagemagick libmagick++-dev libmagic-dev libmagickwand-dev vim libpq-dev && apt-get clean

# Install Chrome WebDriver
RUN CHROMEDRIVER_VERSION=`curl -sS chromedriver.storage.googleapis.com/LATEST_RELEASE` && \
    mkdir -p /opt/chromedriver-$CHROMEDRIVER_VERSION && \
    curl -sS -o /tmp/chromedriver_linux64.zip http://chromedriver.storage.googleapis.com/$CHROMEDRIVER_VERSION/chromedriver_linux64.zip && \
    apt-get -yqq install unzip && \
    unzip -qq /tmp/chromedriver_linux64.zip -d /opt/chromedriver-$CHROMEDRIVER_VERSION && \
    rm /tmp/chromedriver_linux64.zip && \
    chmod +x /opt/chromedriver-$CHROMEDRIVER_VERSION/chromedriver && \
    ln -fs /opt/chromedriver-$CHROMEDRIVER_VERSION/chromedriver /usr/local/bin/chromedriver

# Install Google Chrome
RUN curl -sS -o - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list && \
    apt-get -yqq update && \
    apt-get -yqq install google-chrome-stable && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile* ./
RUN gem install bundler
RUN bundle install

COPY . /app

# add encription key to decode secrets
ARG RAILS_MASTER_KEY

RUN echo "RAILS_ENV: $RAILS_ENV" && rake assets:precompile RAILS_ENV=$RAILS_ENV

EXPOSE 3000
CMD ["rails", "server", "-b", "0.0.0.0"]