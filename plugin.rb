# name: discourse-private-replies
# about: DiscourseHosting private replies plugin
# version: 0.1
# authors: dujiajun
# url: https://github.com/dujiajun/discourse-private-replies

enabled_site_setting :private_replies_enabled

register_svg_icon "user-secret" if respond_to?(:register_svg_icon)

load File.expand_path('../lib/discourse_private_replies/engine.rb', __FILE__)

after_initialize do
  
  # hide posts from the /raw/tid/pid route
  class ::Guardian
    module PatchPostGuardian
      def can_see_post?(post)
        return false unless super(post)
        return true if is_admin? 

        if SiteSetting.private_replies_enabled && post.topic.custom_fields.keys.include?('private_replies') && post.topic.custom_fields['private_replies']
          replied_users = Post.where('topic_id = ? AND deleted_at IS NULL' ,post.topic).pluck(:user_id)
          userids = [ post.topic.user.id ] + replied_users
          return false unless userids.include? @user.id
        end
        true
      end
    end
    prepend PatchPostGuardian
  end

  # hide posts from the regular topic stream
  module PatchTopicView

    # hide posts at the lowest level
    def unfiltered_posts
      result = super
      
      if SiteSetting.private_replies_enabled && @topic.custom_fields.keys.include?('private_replies') && @topic.custom_fields['private_replies']
        if !@user
          result = result.where('posts.post_number = 1')
        end
        if @topic.user.id != @user.id && !@user.admin?   # Topic starter and admin can see it all
          replied_users = Post.where('topic_id = ? AND deleted_at IS NULL' ,@topic.id).pluck(:user_id)
          if not (replied_users.include?(@user.id))
            result = result.where('posts.post_number = 1')
          end
        end
      end
      result
    end

    # filter posts_by_ids does not seem to use unfiltered_posts ?! WHY...
    # so we need to filter that separately
    def filter_posts_by_ids(post_ids)
      @posts = super(post_ids)
      if SiteSetting.private_replies_enabled && @topic.custom_fields.keys.include?('private_replies') && @topic.custom_fields['private_replies']
        if !@user
          @posts = @posts.where('posts.post_number = 1')
        end
        if @topic.user.id != @user.id && !@user.admin?   # Topic starter and admin can see it all
          replied_users = Post.where('topic_id = ? AND deleted_at IS NULL' ,@topic.id).pluck(:user_id)
          if not (replied_users.include?(@user.id))
            @posts = @posts.where('posts.post_number = 1')
          end
        end
      end
      @posts
    end
  end

  # hide posts from search results
  module PatchSearch
  
    def execute(readonly_mode)
      super

      if SiteSetting.private_replies_enabled
        
        protected_topics = TopicCustomField.where(:name => 'private_replies').where(:value => true).pluck(:topic_id)
        
        @results.posts.delete_if do |post|
          next false unless protected_topics.include? post.topic_id # leave unprotected topics alone
          replied_users = Post.where('topic_id = ? AND deleted_at IS NULL', post.topic_id).pluck(:user_id)
          next false if @guardian.user && replied_users.include?(@guardian.user.id)  # show my replied topics' posts
          true
        end
      end
      
      @results
    end
  end

  class ::TopicView
    prepend PatchTopicView
  end

  class ::Search
    prepend PatchSearch
  end

  Topic.register_custom_field_type('private_replies', :boolean)
  add_to_serializer :topic_view, :private_replies do
    object.topic.custom_fields['private_replies'] 
  end
   
  Discourse::Application.routes.append do
    mount ::DiscoursePrivateReplies::Engine, at: "/private_replies"
  end

end

