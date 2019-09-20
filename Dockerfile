FROM ruby:2.6.4-stretch
MAINTAINER Darin London <darin.london@duke.edu>

ARG CI_COMMIT_SHA=unspecified
LABEL git_commit=${CI_COMMIT_SHA}

ARG CI_PROJECT_URL=unspecified
LABEL git_repository_url=${CI_PROJECT_URL}

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
# ensure root group ownership of the app directory for okd
RUN chgrp -R root /opt/app-root/src/ \
    && chmod -R g=rwx /opt/app-root/src/
