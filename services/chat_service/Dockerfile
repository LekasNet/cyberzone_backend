FROM dart:stable

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .

EXPOSE 8085

CMD ["dart", "run", "bin/chat_service.dart"]
