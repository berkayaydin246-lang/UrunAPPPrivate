-- Example temporary policies for admin imports
-- Use carefully in development environments

create policy "allow ingredient inserts"
on ingredients
for insert
to anon
with check (true);

create policy "allow product inserts"
on products
for insert
to anon
with check (true);

create policy "allow review inserts"
on product_reviews
for insert
to anon
with check (true);

create policy "allow product ingredient inserts"
on product_ingredients
for insert
to anon
with check (true);