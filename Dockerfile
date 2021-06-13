FROM ruby:2.7.3-alpine3.13

RUN apk update
RUN apk add g++ make openssl
RUN gem install discordrb dotenv
RUN mkdir /app
WORKDIR /app
CMD ["ruby", "bot.rb"]
