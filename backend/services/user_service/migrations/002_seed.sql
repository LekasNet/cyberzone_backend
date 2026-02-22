-- User Service seed data (roles, disciplines)
INSERT INTO roles (id, name) VALUES
  ('522906fb-b07e-4e00-b6e0-6842155acd53', 'Commentator'),
  ('a7e467ad-3b33-41cd-b42a-7a00adddfb25', 'Analyst'),
  ('7f0457bd-a5a6-4842-8206-11cf73caa89f', 'Judge'),
  ('03459e9f-f9e8-4856-bb05-c17fec06c475', 'Observer'),
  ('8385e1e6-87a4-4c12-92d5-219cd93a9fbb', 'Sound Engineer'),
  ('c0785158-323d-4da6-a806-74b1720249c6', 'Operator'),
  ('0bdf62f3-5b52-4e6d-b228-6172eef7d033', 'Photographer'),
  ('beb0f928-4c5c-4450-b80d-0ee9951cb1e1', 'Cosplayer')
ON CONFLICT (name) DO NOTHING;

INSERT INTO disciplines (id, name) VALUES
  ('cd4f7e36-64c0-4a04-a1d0-2d36dc3848c0', 'CS'),
  ('f2cd27a3-7a94-4e37-bf1a-3442c3f07034', 'Dota'),
  ('999b166f-2799-4094-b459-1812337060b8', 'LoL')
ON CONFLICT (name) DO NOTHING;
