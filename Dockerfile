FROM ruby:2.6.4-stretch
MAINTAINER Darin London <darin.london@duke.edu>

RUN apt-get update -qq \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
      jq \
    && rm -rf /var/lib/apt/lists/*


ENV APP_PATH /opt/app-root/src
ENV HOME ${APP_PATH}
WORKDIR ${APP_PATH}
ADD Gemfile $APP_PATH
RUN bundle install --retry 3

# Copy the application into the container
COPY . $APP_PATH
RUN chgrp -R root /opt/app-root/src/ \
    && chmod -R g=rwx /opt/app-root/src/
