class MemberFollowing < ApplicationRecord
  @@limit = 10
  include AppConstants
  
  belongs_to :member_profile
  
  def self.search_member(data, current_user)
    begin
      data = data.with_indifferent_access
      per_page = (data[:per_page] || @@limit).to_i
      page     = (data[:page] || 1).to_i
      users    = User.all
      if data[:search_key].present?
        profile_ids = users.where('username LIKE ? OR email LIKE ?',"%#{data[:search_key]}%", "%#{data[:search_key]}%").pluck(:profile_id)
      else
        profile_ids = users.pluck(:profile_id)
      end
      if profile_ids.present?
        member_profiles = MemberProfile.where(id: profile_ids)

        member_profiles = member_profiles.page(page.to_i).per_page(per_page.to_i)
        paging_data = JsonBuilder.get_paging_data(page, per_page, member_profiles)

        resp_data = response_member_profiles(member_profiles, current_user)

        resp_status = 1
        resp_message = 'success'
        resp_errors = ''
      else
        resp_data = {}
        resp_status = 1
        resp_message = 'success'
        resp_errors = 'No string match found.'
      end
    rescue Exception => e
      resp_data       = {}
      resp_status     = 0
      paging_data     = ''
      resp_message    = 'error'
      resp_errors     = e
    end
    resp_request_id   = data[:request_id]
    JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors, paging_data: paging_data)
  end

  def self.response_member_profiles(member_profiles, current_user)
    # member_profiles = member_profiles.as_json(
    #     {
    #         only: [:id, :photo],
    #         methods: [:is_im_following, ],
    #         include: {
    #             user: {
    #                 only: [:id, :username, :email]
    #             }
    #         }
    #     }
    # )
    member_profiles = member_profiles.to_xml(
        only: [:id, :photo],
        :procs => Proc.new { |options, member_profile|
          options[:builder].tag!('is_following', MemberProfile.is_following(member_profile, current_user))
          options[:builder].tag!('is_follower',  MemberProfile.is_following(member_profile, current_user))
        },
        include: {
            user: {
                only: [:id, :email, :username]
            }
        }
    )
    Hash.from_xml(member_profiles).as_json

    # {member_profiles: member_profiles}.as_json
  end

  def self.follow_member(data, current_user)
    begin
      data = data.with_indifferent_access

      member_profile       = current_user.profile
      member_following    = MemberFollowing.find_by_member_profile_id_and_following_profile_id(member_profile.id, data[:following_profile_id])
      following_to_profile = MemberProfile.find(data[:following_profile_id])
      is_accepted = false
      if member_following.blank?
        member_following   =  member_profile.member_followings.build
        member_following.following_profile_id = data[:following_profile_id]
        if following_to_profile #&& following_to_profile.is_profile_public
          member_following.following_status = AppConstants::ACCEPTED
          resp_message = 'Following Request Submitted'
          is_accepted  = true
        else
          # send_notification(data[:member_following][:following_profile_id])
          resp_message = 'Request sent.'
        end
        member_following.save!
        resp_status = 1
        resp_errors = ''
      else
        member_following.following_status = AppConstants::ACCEPTED
        member_following.is_deleted = false
        member_following.save!
        is_accepted  = true
        resp_message = 'Following Request Submitted.'
        resp_status  = 1
        resp_errors  = ''
      end
      resp_data      = {is_im_following: MemberProfile.is_following(following_to_profile, current_user)}
    rescue Exception => e
      resp_data      = {}
      resp_status    = 0
      resp_message   = 'error101'
      resp_errors    = e
    end
    resp_request_id = data[:request_id]
    response = JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors)
    if is_accepted == 1
      begin
        member_following_notification(member_following, current_user)
      rescue Exception => e
      end
    end
    [response, is_accepted]
  end

  def self.unfollow_member(data, current_user)
    begin
      data             =  data.with_indifferent_access
      member_following =  MemberFollowing.find_by_member_profile_id_and_following_profile_id(current_user.profile_id, data[:following_profile_id])
      if member_following.present?
        member_following.is_deleted = true
        member_following.save!
        # Remove from groups
        profile = current_user.profile
        groups = profile.groups
        if groups.present?
          groups.each do |group|
            group_member = GroupMember.where(group_id: group.id, member_profile_id: data[:following_profile_id])
            group_member.destroy_all if group_member.present?
          end
        end
        resp_status = 1
        resp_message = 'Unfollow Successfull.'
        resp_errors = ''
      else
        resp_status = 0
        resp_message = 'Errors'
        resp_errors = 'No Follower Found.'
      end
      following_to_profile = MemberProfile.find_by_id(data[:following_profile_id])
      resp_data    = {is_im_following: MemberProfile.is_following(following_to_profile, current_user)}
    rescue Exception => e
      resp_data       = {}
      resp_status     = 0
      paging_data     = ''
      resp_message    = 'error'
      resp_errors     = e
    end
    resp_request_id = data[:request_id]
    JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors)
  end

  def self.accept_reject_follower(data, current_user)
    begin
      data = data.with_indifferent_access
      #profile          =  current_user.profile

      member_following = MemberFollowing.find_by_id(data[:member_following][:id])
      member_following.following_status = data[:member_following][:following_status]
      member_following.save!
      resp_data     = {}
      resp_status   = 1
      resp_message  = 'Invitation' + ' '+ member_following.following_status
      resp_errors   = ''
    rescue Exception => e
      member_following = 0
      resp_data     = {}
      resp_status   = 0
      resp_message  = 'error'
      resp_errors   = e
    end
    resp_request_id   = data[:request_id]
    JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, member_following,errors: resp_errors)
    # [response, resp_status, member_following]
  end

  def self.get_followers(data, current_user)
     begin
      data = data.with_indifferent_access
      per_page = (data[:per_page] || @@limit).to_i
      page     = (data[:page] || 1).to_i

      profile = MemberProfile.find_by_id(data[:member_profile][:id])
      member_followings = MemberFollowing.where(following_status: AppConstants::ACCEPTED, following_profile_id: profile.id, is_deleted: false) if profile.present?
      if data[:member_profile][:search_key].present?
        profile_ids     = member_followings.pluck(:member_profile_id)
        # member_profiles = MemberProfile.where(id: profile_ids)
        users = User.where("username @@ :q or email @@ :q", q: "%#{data[:member_profile][:search_key]}%")
        searched_profile_ids = users.where(profile_id: profile_ids).pluck(:profile_id)
        member_followings = MemberFollowing.where(following_status: AppConstants::ACCEPTED, following_profile_id: profile.id, is_deleted: false, member_profile_id: searched_profile_ids)
      end
      if member_followings.present?
        member_followings = member_followings.page(page.to_i).per_page(per_page.to_i)
        paging_data = JsonBuilder.get_paging_data(page, per_page, member_followings)

        resp_data     = member_followings_response(member_followings, current_user, profile, AppConstants::MEMBER_FOLLOWERS, true)
        resp_status   = 1
        resp_message  = 'success'
        resp_errors   = ''
      else
        resp_data = []
        paging_data = nil
        resp_status = 0
        resp_message = 'error'
        resp_errors = 'No one following you.'
      end
    rescue Exception => e
      resp_data       = ''
      resp_status     = 0
      paging_data     = ''
      resp_message    = 'error'
      resp_errors     = e
    end
    resp_request_id = data[:request_id]
    JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors, paging_data: paging_data)
  end

  def self.get_following_members(data, current_user)
    begin
      data = data.with_indifferent_access
      per_page = (data[:per_page] || @@limit).to_i
      page     = (data[:page] || 1).to_i

      profile   = MemberProfile.find_by_id(data[:member_profile][:id])
      member_followings = profile.member_followings.where(following_status: AppConstants::ACCEPTED, is_deleted: false) if profile.present?
      if data[:member_profile][:search_key].present?
        profile_ids     = member_followings.pluck(:following_profile_id)
        # member_profile = MemberProfile.where(id: profile_ids)
        users = User.where("username @@ :q or email @@ :q", q: "%#{data[:member_profile][:search_key]}%")
        searched_profile_ids = users.where(profile_id: profile_ids).pluck(:profile_id)
        member_followings = profile.member_followings.where(following_status: AppConstants::ACCEPTED, is_deleted: false, following_profile_id: searched_profile_ids)
      end
      if member_followings.present?
        member_followings = member_followings.page(page.to_i).per_page(per_page.to_i)
        paging_data = JsonBuilder.get_paging_data(page, per_page, member_followings)
        resp_data = member_followings_response(member_followings, current_user, profile, AppConstants::MEMBER_FOLLOWINGS, true)
        resp_status = 1
        resp_message = 'success'
        resp_errors = ''
      else
        resp_data = []
        resp_status = 0
        resp_message = 'error'
        resp_errors = 'You are not following to other.'
        paging_data = nil
      end
    rescue Exception => e
      resp_data       = ''
      resp_status     = 0
      paging_data     = ''
      resp_message    = 'error'
      resp_errors     = e
    end
    resp_request_id = data[:request_id]
    JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors, paging_data: paging_data)
  end

  def self.member_followings_response(member_followings, current_user, searched_profile,root, root_status=nil)
    response = []
    member_followings.each do |member_following|
      if root && root == AppConstants::MEMBER_FOLLOWINGS
        profile = MemberProfile.find_by_id(member_following.following_profile_id)
      else
        profile = member_following.member_profile
      end
      user              = profile.user

      # member_following =  MemberFollowing.where(following_status: ACCEPTED, member_profile_id: current_user.profile.id, following_profile_id: profile.id)
      is_current_user_following =  MemberFollowing.find_by_member_profile_id_and_following_profile_id_and_following_status_and_is_deleted(current_user.profile_id, profile.id, AppConstants::ACCEPTED,false)
      is_current_user_follower  =  MemberFollowing.find_by_member_profile_id_and_following_profile_id_and_following_status_and_is_deleted(profile.id, current_user.profile_id, AppConstants::ACCEPTED,false)

      response << {
          id:                   member_following.id,
          member_profile_id:    member_following.member_profile_id,
          following_profile_id: member_following.following_profile_id,
          following_status:     member_following.following_status,
          created_at:           member_following.created_at,
          updated_at:           member_following.updated_at,
          member_profile:{
              id:               profile.id,
              photo:            profile.photo,
              is_im_following:  is_current_user_following ? true : false,
              is_my_follower:   is_current_user_follower  ? true : false,

              user:{
                  id:           user.id,
                  username:     user.username,
                  email:        user.email
              }
          }
      }

    end
    
    if current_user.profile_id != searched_profile.id
      is_current_user_following =  MemberFollowing.find_by_member_profile_id_and_following_profile_id_and_following_status_and_is_deleted(current_user.profile.id, searched_profile.id, ACCEPTED,false)
      is_current_user_follower  =  MemberFollowing.find_by_member_profile_id_and_following_profile_id_and_following_status_and_is_deleted(searched_profile.id, current_user.profile.id, ACCEPTED,false)
    else
      is_current_user_following = false
      is_current_user_follower  = false
    end
    searched_user = searched_profile.user
    profile = {
        id:               searched_profile.id,
        photo:            searched_profile.photo,
        is_im_following:  is_current_user_following ? true : false,
        is_my_follower:   is_current_user_follower  ? true : false,
        user:{
            id:            searched_user.id,
            username:      searched_user.username,
            email:         searched_user.email
        }
    }
    if root_status.present?
      {"#{root}": response, member_profile: profile}.as_json
    else
      response
    end
  end

  def self.send_notification(data)
    user_to_following = MemberProfile.find(data).user
    if user_to_following.user_sessions.where(session_status: 'open').present?
      # user_session_to_following = user_to_following.user_sessions.last
      resp_data = ''
      resp_request_id = ''
      resp_status = 1
      resp_message = "You have new invitation."
      resp_errors = ''
      response = JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors)
      ActionCable.server.broadcast "profile_channel_#{user_to_following.id}", response
    end
  end

  def self.get_following_pending_requests(data, current_user)
    begin
      data = data.with_indifferent_access
      per_page = (data[:per_page] || @@limit).to_i
      page     = (data[:page] || 1).to_i

      profile = current_user.profile
      # member_followings  = profile.member_followings.where(following_status: AppConstants::PENDING)
      member_followers  = MemberFollowing.where(following_profile_id: current_user.profile_id, following_status: AppConstants::PENDING, is_deleted: false)

      if member_followers.present?
        member_followers = member_followers.page(page.to_i).per_page(per_page.to_i)
        paging_data = JsonBuilder.get_paging_data(page, per_page, member_followers)

        resp_data       = member_followings_response(member_followers, current_user, profile, AppConstants::MEMBER_FOLLOWERS, true)
        resp_status     = 1
        resp_message    = 'success'
        resp_errors     = ''
      else
        resp_data       = []
        resp_status     = 0
        paging_data     = nil
        resp_message    = 'error'
        resp_errors     = 'You have not pending request.'
      end
    rescue Exception => e
      resp_data       = ''
      resp_status     = 0
      paging_data     = ''
      resp_message    = 'error'
      resp_errors     = e
    end
    resp_request_id = data[:request_id]
    JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors, paging_data: paging_data)
  end

  def self.get_followers_pending_requests(data, current_user)
    data = data.with_indifferent_access
    per_page = (data[:per_page] || @@limit).to_i
    page     = (data[:page] || 1).to_i

    profile = current_user.profile

    member_followings  = MemberFollowing.where(following_profile_id: profile.id, following_status: PENDING)
    # member_followings  = profile.member_followings.where(following_status: PENDING)

    if member_followings.present?
      member_followings = member_followings.page(page.to_i).per_page(per_page.to_i)
      paging_data       = JsonBuilder.get_paging_data(page, per_page, member_followings)

      resp_data       = member_followings_response(member_followings, current_user, profile, MEMBER_FOLLOWINGS, true)
      resp_status     = 1
      resp_message    = 'success'
      resp_errors     = ''
    else
      resp_data       = []
      resp_status     = 0
      paging_data     = nil
      resp_message    = 'error'
      resp_errors     = 'You have not pending request.'
    end

    resp_request_id = data[:request_id]
    JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors, paging_data: paging_data)
  end

  def self.member_following_notification(member_following, current_user)
    name  =  current_user.username || current_user.email
    following_to_profile  = MemberProfile.find(member_following.following_profile_id)
    if member_following.following_status  ==  AppConstants::ACCEPTED
      alert  = name + ' ' + AppConstants::START_FOLLOWING_YOU
    else
      alert  = name + ' ' + AppConstants::FRIEND_REQUEST
    end
    screen_data = {member_following_id: member_following.id, status: member_following.following_status, member_profile_id: member_following.member_profile_id}.as_json
    Notification.send_event_notification(following_to_profile.user, alert, AppConstants::FOLLOWER_SCREEN, true, screen_data)
  end
end

# == Schema Information
#
# Table name: member_followings
#
#  id                   :integer          not null, primary key
#  member_profile_id    :integer
#  following_profile_id :integer
#  following_status     :string           default("pending")
#  is_deleted           :boolean          default(FALSE)
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#

