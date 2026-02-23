FROM dart:stable

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .

EXPOSE 8084

CMD ["dart", "run", "bin/rating_service.dart"]
