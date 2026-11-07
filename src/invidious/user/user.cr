require "db"

struct Invidious::User
  include DB::Serializable

  property updated : Time
  property notifications : Array(String)
  property subscriptions : Array(String)
  property email : String

  @[DB::Field(converter: Invidious::User::PreferencesConverter)]
  property preferences : Preferences
  property password : String?
  property token : String
  property watched : Array(String)
  property feed_needs_update : Bool?
  # IMPORTANT: Users.insert() is a positional INSERT (user.to_a) whose
  # argument order is this struct's property declaration order. It must
  # match the users table's physical column order. blacklist is appended
  # last by migration 0011 (ALTER TABLE ADD COLUMN always appends), so
  # the property must stay last — moving it up silently shifts every
  # column after it and breaks account creation (PQ::PQError malformed
  # array literal). config/sql/users.sql must list it last too.
  property blacklist : Array(String)

  module PreferencesConverter
    def self.from_rs(rs)
      begin
        Preferences.from_json(rs.read(String))
      rescue
        Preferences.from_json("{}")
      end
    end
  end
end
