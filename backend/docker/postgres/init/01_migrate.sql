\set ON_ERROR_STOP on

\connect cyberzone_auth
\i /workspace/services/auth_service/migrations/001_init.sql

\connect cyberzone_user
\i /workspace/services/user_service/migrations/001_init.sql
\i /workspace/services/user_service/migrations/002_seed.sql

\connect cyberzone_schedule
\i /workspace/services/schedule_service/migrations/001_init.sql

\connect cyberzone_event
\i /workspace/services/event_service/migrations/001_init.sql

\connect cyberzone_rating
\i /workspace/services/rating_service/migrations/001_init.sql

\connect cyberzone_chat
\i /workspace/services/chat_service/migrations/001_init.sql

\connect cyberzone_notification
\i /workspace/services/notification_service/migrations/001_init.sql
