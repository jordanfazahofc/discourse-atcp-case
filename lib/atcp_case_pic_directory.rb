# frozen_string_literal: true

# Membangun struktur departemen PIC untuk form kasus dari
# SiteSetting.atcp_case_pic_departments ("Departemen: username1, username2").
# Kandidat hanya anggota Internal (group di atcp_internal_groups_map) + admin,
# dibatasi user nyata, aktif, dan tidak sedang suspended. Departemen tanpa satu
# pun anggota valid tidak ditampilkan. User kandidat yang tidak disebut di
# setting dikumpulkan ke kelompok "Other" (selalu terakhir, dihilangkan bila
# kosong).
class AtcpCasePicDirectory
  def self.groups(
    setting: SiteSetting.atcp_case_pic_departments,
    group_ids: SiteSetting.atcp_internal_groups_map,
    user_scope: User.real.activated.not_suspended
  )
    new(setting: setting, group_ids: group_ids, user_scope: user_scope).groups
  end

  # Satu-satunya aturan kelayakan PIC: user nyata, aktif, tidak suspended,
  # bukan bot, bukan staged, dan lolos gerbang Internal.
  def self.candidate?(user)
    return false if user.nil?
    return false unless user.active?
    return false if user.bot?
    return false if user.suspended?
    return false if user.staged?

    Atcp::InternalAccess.allowed?(user)
  end

  def initialize(setting:, group_ids:, user_scope:)
    @setting = setting.to_s
    @group_ids = Array(group_ids).map(&:to_i)
    @user_scope = user_scope
  end

  def groups
    candidates = candidate_users
    by_username = candidates.index_by { |user| user.username.downcase }
    seen = Set.new
    result = []

    @setting.each_line do |raw_line|
      name, usernames = raw_line.split(":", 2)
      next if usernames.nil?

      name = name.strip
      next if name.blank?

      users =
        usernames
          .split(",")
          .filter_map do |value|
            key = value.strip.downcase
            next if key.blank? || seen.include?(key)

            user = by_username[key]
            next if user.nil?

            seen << key
            user
          end

      if users.any?
        result << {
          name: name,
          users: users.map { |user| serialize_user(user) }
        }
      end
    end

    others =
      candidates
        .reject { |user| seen.include?(user.username.downcase) }
        .sort_by { |user| user.username.downcase }
    if others.any?
      result << {
        name: "Other",
        users: others.map { |user| serialize_user(user) }
      }
    end

    result
  end

  private

  def candidate_users
    @candidate_users ||=
      @user_scope
        .where(admin: true)
        .or(
          @user_scope.where(
            id: GroupUser.where(group_id: @group_ids).select(:user_id)
          )
        )
        .to_a
  end

  def serialize_user(user)
    { id: user.id, username: user.username, name: user.name }
  end
end
