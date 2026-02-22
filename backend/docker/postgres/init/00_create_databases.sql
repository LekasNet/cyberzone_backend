-- Create databases for services
SELECT 'CREATE DATABASE cyberzone_auth OWNER cyberzone'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cyberzone_auth')\gexec

SELECT 'CREATE DATABASE cyberzone_user OWNER cyberzone'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cyberzone_user')\gexec

SELECT 'CREATE DATABASE cyberzone_schedule OWNER cyberzone'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cyberzone_schedule')\gexec

SELECT 'CREATE DATABASE cyberzone_event OWNER cyberzone'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cyberzone_event')\gexec

SELECT 'CREATE DATABASE cyberzone_rating OWNER cyberzone'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cyberzone_rating')\gexec

SELECT 'CREATE DATABASE cyberzone_chat OWNER cyberzone'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cyberzone_chat')\gexec

SELECT 'CREATE DATABASE cyberzone_notification OWNER cyberzone'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cyberzone_notification')\gexec
