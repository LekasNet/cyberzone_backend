FROM dart:stable

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .

EXPOSE 8083

CMD ["dart", "run", "bin/event_service.dart"]
