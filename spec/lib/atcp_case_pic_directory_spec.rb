# frozen_string_literal: true

require_relative "../../lib/atcp_case_pic_directory"

RSpec.describe AtcpCasePicDirectory do
  fab!(:group)
  fab!(:second_group, :group)
  fab!(:admin_user, :admin)
  fab!(:alice, :user)
  fab!(:bob, :user)
  fab!(:carol, :user)
  fab!(:dave, :user)

  before do
    group.add(alice)
    group.add(bob)
    second_group.add(carol)
  end

  def directory(setting)
    described_class.groups(
      setting: setting,
      group_ids: [group.id, second_group.id],
      user_scope:
        User.real.activated.not_suspended.where(
          id: [alice.id, bob.id, carol.id, dave.id, admin_user.id]
        )
    )
  end

  def usernames_for(result, name)
    result.find { |entry| entry[:name] == name }[:users].map do |user|
      user[:username]
    end
  end

  it "lists departments in setting order with case-insensitive username matching" do
    result =
      directory(
        "Support: #{alice.username.upcase}, #{bob.username}\nQC: #{carol.username}"
      )

    expect(result.map { |entry| entry[:name] }).to eq(%w[Support QC Other])
    expect(usernames_for(result, "Support")).to eq(
      [alice.username, bob.username]
    )
    expect(usernames_for(result, "QC")).to eq([carol.username])
    expect(usernames_for(result, "Other")).to eq([admin_user.username])
  end

  it "ignores usernames that are not internal candidates" do
    result = directory("Support: #{alice.username}, #{dave.username}")

    expect(usernames_for(result, "Support")).to eq([alice.username])
    expect(usernames_for(result, "Other")).to contain_exactly(
      admin_user.username,
      bob.username,
      carol.username
    )
  end

  it "puts every candidate not listed in a department into Other, always last" do
    result = directory("Support: #{alice.username}")

    expect(result.last[:name]).to eq("Other")
    expect(usernames_for(result, "Other")).to contain_exactly(
      admin_user.username,
      bob.username,
      carol.username
    )
  end

  it "omits Other when every candidate is listed" do
    result =
      directory(
        "Support: #{alice.username}\nQC: #{bob.username}, #{carol.username}, #{admin_user.username}"
      )

    expect(result.map { |entry| entry[:name] }).to eq(%w[Support QC])
  end

  it "ignores blank lines and lines without a usable department name" do
    result = directory("Support: #{alice.username}\n\nnot a department\n:")

    expect(result.map { |entry| entry[:name] }).to eq(%w[Support Other])
    expect(usernames_for(result, "Support")).to eq([alice.username])
  end

  it "keeps only the first department when a username appears twice" do
    result = directory("Support: #{alice.username}\nQC: #{alice.username}")

    expect(usernames_for(result, "Support")).to eq([alice.username])
    expect(usernames_for(result, "QC")).to eq([])
  end

  it "keeps named departments that have no users" do
    result = directory("Support: does_not_exist")

    expect(result.map { |entry| entry[:name] }).to eq(%w[Support Other])
    expect(usernames_for(result, "Support")).to eq([])
  end

  it "excludes suspended members" do
    alice.update!(suspended_till: 1.year.from_now)

    result = directory("Support: #{alice.username}, #{bob.username}")

    expect(usernames_for(result, "Support")).to eq([bob.username])
    expect(usernames_for(result, "Other")).to contain_exactly(
      admin_user.username,
      carol.username
    )
  end

  it "only considers active users" do
    bob.update!(active: false)

    result = directory("Support: #{alice.username}, #{bob.username}")

    expect(usernames_for(result, "Support")).to eq([alice.username])
    expect(usernames_for(result, "Other")).to contain_exactly(
      admin_user.username,
      carol.username
    )
  end
end
