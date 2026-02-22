FROM dart:stable

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .

EXPOSE 8086

CMD ["dart", "run", "bin/notification_service.dart"]
