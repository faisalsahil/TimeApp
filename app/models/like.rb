class Like < ApplicationRecord
  include JsonBuilder
  
  # belongs_to :post, :counter_cache => true
  belongs_to :likable, polymorphic: true
  belongs_to :member_profile
  
  @@limit = 10
  
  def self.liked_by_me(post, profile_id)
    post_like = post.likes.where(member_profile_id: profile_id).try(:first)
    if post_like && post_like.is_like
      true
    else
      false
    end
  end
  
  def self.like(data, current_user)
    begin
      data                        = data.with_indifferent_access
      post                        = Post.find_by_id(data[:post][:id])
      # if post.event.end_date > DateTime.now
        post_like                   = Like.find_by_likable_id_and_member_profile_id(post.id, current_user.profile_id) || post.likes.build
        post_like.member_profile_id = current_user.profile_id
        post_like.is_like           = data[:post][:is_like]
        if post_like.save
          resp_data       = like_response(post_like)
          post_comments   = []
          resp_broadcast  = Comment.comments_response(post_comments, current_user, post)
          resp_status     = 1
          resp_errors     = ''
          data[:post][:is_like] == true || data[:post][:is_like] == 1 ? resp_message = AppConstants::LIKED : resp_message = AppConstants::DISLIKED
        else
          resp_data       = {}
          resp_broadcast  = ''
          resp_status     = 0
          resp_message    = 'Errors'
        end
      # else
      #   resp_data       = {}
      #   resp_broadcast  = ''
      #   resp_status     = 0
      #   resp_message    = 'You can\'t vote on the closed event.'
      # end
      resp_request_id = data[:request_id]
      response        = JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors)
      [response, resp_broadcast]
    rescue Exception => e
      resp_data       = {}
      resp_status     = 0
      resp_message    = 'error'
      resp_errors     = e
      resp_request_id = data[:request_id]
      JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id: resp_request_id, errors: resp_errors)
    end
  end
  
  def self.like_response(like)
    like = like.as_json(
        only: [:id, :likable_id, :likable_type],
        include:{
            member_profile: {
                only: [:id, :photo],
                include:{
                    user:{
                        only:[:id, :username, :email]
                    }
                }
            },
            likable: {
                only: [:id],
                methods: [:likes_count]
            }
        }
    )
    
    {like: like}.as_json
  end
  
  def self.broadcast_like(response, object_id,  object_type)
    begin
      resp_message    = AppConstants::LIKED
      resp_request_id = ''
      resp_status     = 1
      resp_errors     = ''
      open_sessions = OpenSession.where(media_id: object_id, media_type: AppConstants::POST)
      open_sessions.each do |open_session|
        broadcast_response = response.merge!(session_id: open_session.session_id)
        broadcast_response = JsonBuilder.json_builder(broadcast_response, resp_status, resp_message, resp_request_id, errors: resp_errors, type: "Sync")
        PostJob.perform_later broadcast_response, open_session.user_id
      end
    rescue Exception => e
      resp_data       = {}
      resp_status     = 0
      resp_message    = 'error'
      resp_errors     = e
      resp_request_id = data[:request_id]
      JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors)
    end
  end
  
  def self.post_likes_list(data, current_user, sync=nil)
    begin
      data       = data.with_indifferent_access
      per_page   = (data[:per_page] || @@limit).to_i
      page       = (data[:page] || 1).to_i
      post       = Post.find_by_id(data[:post_id])
      post_likes = post.likes.where(is_deleted: false, is_like: true)
      
      if post_likes
        post_likes  = post_likes.page(page.to_i).per_page(per_page.to_i)
        paging_data = JsonBuilder.get_paging_data(page, per_page, post_likes)
        if sync.present?
          resp_data       = post.post_response
        else
          resp_data       = post_likes_response(post_likes)
        end
        
        resp_status     = 1
        resp_message    = 'Post Likes List'
        resp_errors     = ''
      else
        resp_data       = ''
        resp_status     = 0
        resp_message    = 'Errors'
        resp_errors     = 'Post Likes Does not exist'
      end
      resp_request_id = data[:request_id]
      if sync.present?
        JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors, type: "Sync", paging_data: paging_data)
      else
        JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors, paging_data: paging_data)
      end
    rescue Exception => e
      resp_data       = ''
      resp_status     = 0
      paging_data     = ''
      resp_message    = 'error'
      resp_errors     = e
      resp_request_id   = data[:request_id]
      response          = JsonBuilder.json_builder(resp_data, resp_status, resp_message, resp_request_id, errors: resp_errors)
    end
  end
  
  def self. post_likes_response(post_likes_array)
    post_likes =  post_likes_array.as_json(
        only:    [:id, :post_id, :is_like, :created_at, :updated_at],
        include: {
            member_profile: {
                only:    [:id, :photo],
                include: {
                    user: {
                        only: [:id, :username, :email]
                    }
                }
            }
        }
    )
    
    {post_likes: post_likes}.as_json
  end
  
  def self.poll_like_notification(post_id, current_user)
    begin
      post        = Post.find_by_id(post_id)
      profile_ids = post.post_members.pluck(:member_profile_id)
      profile_ids << post.member_profile_id
      users       = User.where(profile_id: profile_ids.uniq)
      ## ======================== Send Notification ========================
      users && users.each do |user|
        if user != current_user
          if user.profile_id == post.member_profile_id
            message = AppConstants::POST_LIKE
          else
            message = AppConstants::POST_LIKE_OTHER
          end
          name = current_user.username || current_user.email
          alert = name + ' ' + message
          screen_data = {post_id: post_id , type: 'like'}.as_json
          Notification.send_event_notification(user, alert, AppConstants::POST, true, screen_data)
        end
      end
        ## ===================================================================
    rescue Exception => e
      puts e
    end
  end
end
