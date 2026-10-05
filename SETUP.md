# セットアップ手順

## A. GitHub Pages で公開する
1. https://github.com/new で `machisuta` という **Public** リポジトリを、README なしの空で作る。
2. このフォルダで実行する(`<ユーザー名>` は置き換える)。
   ```
   git remote add origin https://github.com/<ユーザー名>/machisuta.git
   git push -u origin main
   ```
3. リポジトリの Settings → Pages で、Branch を `main` / `/ (root)` にして Save。
4. 1〜2分後に `https://<ユーザー名>.github.io/machisuta/` で開ける。

## B. Supabase を用意する(フレンド共有用)
1. https://supabase.com でアカウントを作り、New project を作る(無料プランでよい)。
2. 左メニューの SQL Editor に [supabase/schema.sql](supabase/schema.sql) を貼って Run する。
3. Authentication → Providers で、使うログイン方法(Email か Google)を有効にする。
4. Authentication → URL Configuration の Site URL と Redirect URLs に、公開 URL(A の手順4)と `http://localhost:3000` を入れる。
5. Project Settings → API から、次の2つを控える。
   - Project URL
   - `anon` public key(ブラウザに置いてよいキー)
   - **`service_role` key は絶対にコードやリポジトリに入れない。**

## C. 動作確認(SQL Editor で)
- RLS が有効か: Table Editor で3つのテーブルに「RLS enabled」の表示があること。
- 2人のテストユーザーでサインアップし、片方の招待コード(`profiles.invite_code`)を、もう片方で `select add_friend_by_code('コード');` として呼べること。

## 次にコードで足すこと(自分で書く部分)
1. `index.html` に `supabase-js` を CDN で読み込み、ログイン画面を作る。
2. `stamp()` / `unstamp()` で、localStorage に加えて `stamps` へ upsert / delete する。
3. ログイン直後に、localStorage の記録をクラウドへ upsert して統合する(同じ `key` は上書きしない)。
4. フレンド画面を作る: 招待コード表示、コード入力 → `add_friend_by_code`、一覧 → `friend_progress`。
