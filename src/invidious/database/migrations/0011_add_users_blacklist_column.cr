module Invidious::Database::Migrations
  class AddUsersBlacklistColumn < Migration
    version 11

    def up(conn : DB::Connection)
      conn.exec <<-SQL
        ALTER TABLE public.users
        ADD COLUMN IF NOT EXISTS blacklist text[] DEFAULT '{}';
        SQL
    end
  end
end
