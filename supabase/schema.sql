-- まちスタ: フレンド共有用スキーマ
-- Supabase の SQL Editor に貼り付けて実行する。何度実行しても壊れないようにしてある。
-- 方針: テーブルは本人だけが読み書きできる。フレンドへは関数(RPC)経由で「集計だけ」を見せる。

-- ---------- テーブル ----------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '名無しさん' check (char_length(display_name) between 1 and 30),
  invite_code  text not null unique
               default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8)),
  created_at   timestamptz not null default now()
);

create table if not exists public.stamps (
  user_id      uuid not null references auth.users(id) on delete cascade,
  key          text not null,                -- 施設名|緯度|経度(アプリ側のキーと同じ)
  name         text not null,
  address      text not null default '',
  prefecture   text not null default '',
  city         text not null default '',
  lat          double precision not null,
  lng          double precision not null,
  stamped_at   timestamptz not null,
  manual       boolean not null default false,
  licenses     jsonb not null default '[]',
  attributions jsonb not null default '[]',
  primary key (user_id, key)
);
create index if not exists stamps_user_time on public.stamps (user_id, stamped_at desc);

-- フレンド関係。(user_a < user_b) に正規化して、同じ組を2行持たない。
create table if not exists public.friendships (
  user_a     uuid not null references auth.users(id) on delete cascade,
  user_b     uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

-- ---------- RLS(必ず有効にする。無いと公開キーで全データが読める) ----------
alter table public.profiles    enable row level security;
alter table public.stamps      enable row level security;
alter table public.friendships enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select using (id = auth.uid());
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles for insert with check (id = auth.uid());
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists stamps_all_own on public.stamps;
create policy stamps_all_own on public.stamps for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists friendships_select_own on public.friendships;
create policy friendships_select_own on public.friendships for select
  using (auth.uid() in (user_a, user_b));
drop policy if exists friendships_delete_own on public.friendships;
create policy friendships_delete_own on public.friendships for delete
  using (auth.uid() in (user_a, user_b));
-- insert は下の add_friend_by_code() だけが行う(直接 insert は許可しない)

-- ---------- サインアップ時にプロフィールを自動作成 ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- RPC ----------
-- 招待コードでフレンドになる。相手の表示名を返す。
create or replace function public.add_friend_by_code(code text) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  target public.profiles;
begin
  if me is null then raise exception 'ログインが必要です'; end if;
  select * into target from public.profiles where invite_code = upper(trim(code));
  if not found then raise exception '招待コードが見つかりません'; end if;
  if target.id = me then raise exception '自分の招待コードは使えません'; end if;
  insert into public.friendships (user_a, user_b)
    values (least(me, target.id), greatest(me, target.id))
    on conflict do nothing;
  return target.display_name;
end $$;

-- フレンドの進捗(集計のみ。店名や座標は返さない)
create or replace function public.friend_progress()
returns table (friend_id uuid, display_name text, stamp_count bigint, last_stamped_at timestamptz)
language sql security definer stable set search_path = public as $$
  select p.id, p.display_name, count(s.key), max(s.stamped_at)
  from public.friendships f
  join public.profiles p on p.id = case when f.user_a = auth.uid() then f.user_b else f.user_a end
  left join public.stamps s on s.user_id = p.id and s.manual = false
  where auth.uid() in (f.user_a, f.user_b)
  group by p.id, p.display_name
  order by 3 desc;
$$;

-- 未ログインから呼べないようにする
revoke all on function public.add_friend_by_code(text) from public, anon;
revoke all on function public.friend_progress()        from public, anon;
grant execute on function public.add_friend_by_code(text) to authenticated;
grant execute on function public.friend_progress()        to authenticated;
