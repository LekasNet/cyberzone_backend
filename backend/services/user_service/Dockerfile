FROM dart:stable

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .

EXPOSE 8081

CMD ["dart", "run", "bin/user_service.dart"]
