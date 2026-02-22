FROM dart:stable

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .

EXPOSE 8082

CMD ["dart", "run", "bin/schedule_service.dart"]
