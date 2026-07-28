-- User Service seed data (roles, disciplines)
INSERT INTO roles (id, name, color) VALUES
  ('522906fb-b07e-4e00-b6e0-6842155acd53', 'Commentator', '#E53935'),
  ('a7e467ad-3b33-41cd-b42a-7a00adddfb25', 'Analyst', '#1E88E5'),
  ('7f0457bd-a5a6-4842-8206-11cf73caa89f', 'Judge', '#8E24AA'),
  ('03459e9f-f9e8-4856-bb05-c17fec06c475', 'Observer', '#43A047'),
  ('8385e1e6-87a4-4c12-92d5-219cd93a9fbb', 'Sound Engineer', '#FB8C00'),
  ('c0785158-323d-4da6-a806-74b1720249c6', 'Operator', '#6D4C41'),
  ('0bdf62f3-5b52-4e6d-b228-6172eef7d033', 'Photographer', '#3949AB'),
  ('beb0f928-4c5c-4450-b80d-0ee9951cb1e1', 'Cosplayer', '#D81B60')
ON CONFLICT (name) DO NOTHING;

INSERT INTO disciplines (id, name, color) VALUES
  ('cd4f7e36-64c0-4a04-a1d0-2d36dc3848c0', 'CS', '#1B5E20'),
  ('f2cd27a3-7a94-4e37-bf1a-3442c3f07034', 'Dota', '#B71C1C'),
  ('999b166f-2799-4094-b459-1812337060b8', 'LoL', '#0D47A1')
ON CONFLICT (name) DO NOTHING;
