class Api::V1::PostsController < Api::V1::ApiProtectedController
  @@limit = 10
  
  def post_list
    # params ={
    #   auth_token: UserSession.first.auth_token,
    #   "per_page": 10,
    #   "page": 1
    #   # "min_post_date": "2017-05-03T12:06:30.470Z",
    #   # "search_key": "#gaming"
    # }
    user_session = UserSession.find_by_auth_token(params[:auth_token])
    if user_session.present?
      resp_data = Post.post_list(params, user_session.user)
      render json: resp_data
    else
      resp_data = {resp_status: 0, message: 'Invalid Token', error: '', data: {}}
      return render json: resp_data
    end
  end
  
  # call from web
  def index
    if params[:start_date].present? && params[:end_date].present?
      posts =  Post.where('created_at >= ? AND updated_at <= ?', params[:start_date], params[:end_date]).order('created_at DESC')
    else
      posts = Post.all.order('created_at DESC')
    end
    member_profile = AdminProfile.find_by_id(params[:member_profile_id])
    posts        =  posts.page(params[:page].to_i).per_page(params[:per_page].to_i)
    paging_data  =  get_paging_data(params[:page], params[:per_page], posts)
    resp_data    =  Post.posts_array_response(posts, member_profile)
    resp_status  = 1
    resp_message = 'Success'
    resp_errors  = ''
    common_api_response(resp_data, resp_status, resp_message, resp_errors, paging_data)
  end
  
  # Call from web
  def destroy
    post  =  Post.find_by_id(params[:id])
    if post.present?
      post.is_deleted = params[:is_block]
      post.save!
      resp_data    = {}
      resp_status  = 1
      resp_message = 'Success'
      resp_errors  = ''
    else
      resp_data    = {}
      resp_status  = 0
      resp_message = 'error'
      resp_errors  = 'Post not found'
    end
    common_api_response(resp_data, resp_status, resp_message, resp_errors)
  end
  
  # Call from app
  def re_post
    # params ={
    #   "auth_token": UserSession.first.auth_token,
    #   "post_id": "deb3d126-cd4e-4bbb-87c3-34a05e83d0b4"
    # }
    user_session = UserSession.find_by_auth_token(params[:auth_token])
    if user_session.present?
      resp_data, new_post = Post.re_post(params, user_session.user)
      render json: resp_data
      Post.post_sync(new_post.id, user_session.user)
    else
      resp_data = {resp_status: 0, message: 'Invalid Token', error: '', data: {}}
      return render json: resp_data
    end
  end
  
  def search_posts_and_members
    # params ={
    #   auth_token: UserSession.first.auth_token,
    #   "per_page": 10,
    #   "search_key": "#gaming"
    # }
    user_session = UserSession.find_by_auth_token(params[:auth_token])
    if user_session.present?
      posts_response  = Post.post_list(params, user_session.user)
      posts_response  = JSON.parse posts_response
      posts_data      = posts_response['data']['posts'] || []
      
      members_response  = MemberFollowing.search_member(params, user_session.user)
      
      members_response  = JSON.parse members_response
      members_data      = members_response['data']['member_profiles'] || []
      
      response = {
          resp_status: 1,
          message: 'success',
          data:{
            posts: posts_data,
            member_profiles: members_data
          }
      }
      render json: response
    else
      resp_data = {resp_status: 0, message: 'Invalid Token', error: '', data: {}}
      return render json: resp_data
    end
  end

  def show
    # params = {
    #     "auth_token": "asdfghgfds",
    #     "id": "-3cf6-49d1-b78e-53ea2c43b44d"
    # }
    user_session = UserSession.find_by_auth_token(params[:auth_token])
    if user_session.present?
      response = Post.post_show(params, user_session.user)
      render json: response
    else
      resp_data = {resp_data: {}, resp_status: 0, resp_message: 'Invalid Token', resp_error: 'error'}.as_json
      return render json: resp_data
    end
  end
  
  def delete_post
    # params = {
    #     "auth_token": UserSession.last.auth_token,
    #     "id": "9deaec7f-5dcf-4e3f-adfa-be06ee890483"
    # }
    user_session = UserSession.find_by_auth_token(params[:auth_token])
    if user_session.present?
      post = Post.find_by_id(params[:id])
      if post.present? && post.member_profile_id == user_session.user.profile_id
        post.is_deleted = true
        post.save
        response = {resp_data: {}, resp_status: 1, resp_message: 'Post successfully deleted', resp_error: ''}.as_json
      else
        response = {resp_data: {}, resp_status: 0, resp_message: 'Either id is invalid or you are not the owner of the post', resp_error: 'error'}.as_json
      end
      render json: response
    else
      resp_data = {resp_data: {}, resp_status: 0, resp_message: 'Invalid Token', resp_error: 'error'}.as_json
      return render json: resp_data
    end
  end
end
