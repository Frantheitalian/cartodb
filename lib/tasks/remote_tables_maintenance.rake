require 'date'

namespace :cartodb do

  namespace :remotes do

    task :clear, [:username] => [:environment] do |t, args|
      username = args[:username]
      raise 'username required' unless username.present?

      u = ::User.where(username: username).first
      require_relative '../../app/services/visualization/common_data_service'
      deleted = CartoDB::Visualization::CommonDataService.new.delete_common_data_for_user(u)
      puts "Deleted #{deleted} remote visualizations"
    end

    task :clear_org, [:org_name] => [:environment] do |t, args|
      org_name = args[:org_name]
      raise 'organization name required' unless org_name.present?

      require_relative '../../app/services/visualization/common_data_service'
      common_data_service = CartoDB::Visualization::CommonDataService.new
      o = Organization.where(name: org_name).first
      o.users.each { |u|
        common_data_service.delete_common_data_for_user(u)
      }
    end

    desc 'Load common data account remotes. Pass username as first argument. Example: `rake cartodb:remotes:reload[development]`'
    task :reload, [:username] => [:environment] do |t, args|
      username = args[:username]
      raise 'username required' unless username.present?

      u = ::User.where(username: username).first
      require_relative '../../app/services/visualization/common_data_service'
      vis_api_url = get_visualizations_api_url
      CartoDB::Visualization::CommonDataService.new.load_common_data_for_user(u, vis_api_url)
    end

    desc 'Load common data account remotes for a whole organization. Pass organization name as first argument. Example: `rake cartodb:remotes:reload[my_team]`'
    task :reload_org, [:org_name] => [:environment] do |t, args|
      org_name = args[:org_name]
      raise 'organization name required' unless org_name.present?

      require_relative '../../app/services/visualization/common_data_service'
      common_data_service = CartoDB::Visualization::CommonDataService.new
      vis_api_url = get_visualizations_api_url
      o = Organization.where(name: org_name).first
      o.users.each {|u|
        common_data_service.load_common_data_for_user(u, vis_api_url)
      }
    end

    desc 'Load common data account remotes for multiple users, in alphabetical order. If you pass a username, it will do it beginning in the next username'
    task :load_all, [:from_username] => [:environment] do |t, args|
      require_relative '../../app/services/visualization/common_data_service'
      common_data_service = CartoDB::Visualization::CommonDataService.new
      vis_api_url = get_visualizations_api_url
      puts DateTime.now
      # TODO: batch
      users = ::User.order_by(:username)
      users = users.where("username > '#{args[:from_username]}'") unless args[:from_username].nil?
      users.all.each do |user|
        added, updated, not_modified, removed, failed = common_data_service.load_common_data_for_user(user, vis_api_url)
        printf("%20s: +%03d; *%03d; =%03d; -%03d; e%03d\n", user.username, added, updated, not_modified, removed, failed)
      end
      puts DateTime.now
    end

    desc "Invalidate user's date flag and make them refresh data library"
    task :invalidate_common_data => [:environment] do
      require_relative '../../app/helpers/common_data_redis_cache'
      require_relative '../../app/services/visualization/common_data_service'

      invalidate_sql = %Q[
          UPDATE users
          SET last_common_data_update_date = null
          WHERE last_common_data_update_date >= now() - '#{::User::COMMON_DATA_ACTIVE_DAYS} day'::interval;
        ]
      updated_rows = Rails::Sequel.connection.fetch(invalidate_sql).update
      CommonDataRedisCache.new.invalidate
      puts "#{updated_rows} users invalidated"

      # Now we try to add the new common-data request to the cache using the common_data user
      common_data_user = ::User.where(username: Cartodb.config[:common_data]["username"]).first
      if !common_data_user.nil?
        vis_api_url = get_visualizations_api_url
        CartoDB::Visualization::CommonDataService.new.load_common_data_for_user(common_data_user, vis_api_url)
      end
    end

    desc "Initialize Dataset Categories"
    task :init_dataset_categories => [:environment] do
      forced_reset = ENV['forced_reset'] == "true"

      if forced_reset
        puts "Initializing with forced_reset"
        Rails::Sequel.connection.run("ALTER TABLE visualizations DROP CONSTRAINT visualizations_category_fkey;")
        Rails::Sequel.connection.run("DELETE FROM visualization_categories;")
        Rails::Sequel.connection.run("ALTER SEQUENCE visualization_categories_id_seq RESTART;")
        Rails::Sequel.connection.run("UPDATE visualization_categories SET id=DEFAULT;")
      end

      Rails::Sequel.connection.run("INSERT INTO visualization_categories (id, type, name, parent_id, list_order) VALUES
          (-1, 1, 'UNASSIGNED', 0, 0),
          (0, 1, 'ROOT', 0, 0),

          (1, 1, 'Datasets', 0, 0),
          (2, 2, 'Maps', 0, 1),

          (3, 1, 'Energy', 1, 0),
          (4, 1, 'Vessels', 1, 0),
          (5, 1, 'Environmental', 1, 0),
          (6, 1, 'Banking', 1, 0),
          (7, 1, 'Retail', 1, 0),
          (8, 1, 'Points of Interest', 1, 0),
          (9, 1, 'Administrative', 1, 0),
          (10, 1, 'Political', 1, 0),
          (11, 1, 'Infrastructure', 1, 0),
          (12, 1, 'Communications', 1, 0),

          (13, 1, 'Exploration', 3, 0),
          (14, 1, 'Renewable Energy', 3, 0),
          (15, 1, 'Coal', 3, 0),
          (16, 1, 'Natural Gas', 3, 0),
          (17, 1, 'Oil', 3, 0),
          (18, 1, 'Regions', 3, 0),
          (19, 1, 'Agriculture', 3, 0),
          (20, 1, 'Power', 3, 0),
          (21, 1, 'Metals', 3, 0),

          (22, 1, 'Natural Disasters', 5, 0),
          (23, 1, 'Climate', 5, 0),
          (24, 1, 'Administration', 5, 0),
          (25, 1, 'Weather', 5, 0),

          (26, 1, 'Global', 9, 0),
          (27, 1, 'Oceana', 9, 0),
          (28, 1, 'Asia', 9, 0),
          (29, 1, 'South America', 9, 0),
          (30, 1, 'Europe', 9, 0),
          (31, 1, 'North America', 9, 0);
      ")

      if forced_reset
        Rails::Sequel.connection.run("ALTER TABLE visualizations ADD CONSTRAINT visualizations_category_fkey
            FOREIGN KEY (category) REFERENCES visualization_categories(id);")
      end
    end

    desc "Initialize Sample Maps Categories"
    task :init_sample_maps_categories => [:environment] do
      Rails::Sequel.connection.run("UPDATE visualization_categories SET name='Sample Maps' WHERE type=2 AND name='Maps';")

      Rails::Sequel.connection.run("INSERT INTO visualization_categories (id, type, name, parent_id, list_order) VALUES
          (32, 2, 'Environmental Risk', 2, 0),
          (33, 2, 'Merger Impact', 2, 0),
          (34, 2, 'Commodities', 2, 0),
            (35, 2, 'Agriculture', 34, 0),
            (36, 2, 'Coal', 34, 0),
            (37, 2, 'Metals', 34, 0),
            (38, 2, 'Natural Gas', 34, 0),
            (39, 2, 'Oil', 34, 0),
            (40, 2, 'Power', 34, 0),
            (41, 2, 'Renewables', 34, 0),
          (42, 2, 'Market Share', 2, 0),
          (43, 2, 'Geographic Exposure', 2, 0),
          (44, 2, 'Political', 2, 0);
      ")
    end

    desc "Sync category set in Data Library for all datasets to all users"
    task :sync_dataset_categories => [:environment] do
      require_relative '../../app/helpers/common_data_redis_cache'
      require_relative '../../app/services/visualization/common_data_service'

      common_data_user = Cartodb.config[:common_data]["username"]

      lib_datasets = Hash[
        Rails::Sequel.connection.fetch(%Q[
          SELECT name, category FROM visualizations WHERE
            user_id=(SELECT id FROM users WHERE username='#{common_data_user}')
            AND privacy='public' AND type='table';
        ]).all.map { |row| [row.fetch(:name), row.fetch(:category)] }
      ]

      lib_datasets.each { |dataset_name, dataset_category|
        dataset_category ||= 'NULL'
        sql_query = %Q[
          UPDATE visualizations SET category=#{dataset_category} WHERE name='#{dataset_name}' AND (type='table' OR type='remote');
          ]
        updated_rows = Rails::Sequel.connection.fetch(sql_query).update
        CommonDataRedisCache.new.invalidate
        puts "#{updated_rows} datasets named #{dataset_name} set to category #{dataset_category}"
      }
    end

    desc "Sync category set in Data Library to all users"
    task :sync_dataset_category, [:dataset_name] => [:environment] do |t, args|
      require_relative '../../app/helpers/common_data_redis_cache'
      require_relative '../../app/services/visualization/common_data_service'

      common_data_user = Cartodb.config[:common_data]["username"]

      lib_datasets = Hash[
        Rails::Sequel.connection.fetch(%Q[
          SELECT name, category FROM visualizations WHERE
            user_id=(SELECT id FROM users WHERE username='#{common_data_user}')
            AND privacy='public' AND type='table' AND name='#{args[:dataset_name]}';
        ]).all.map { |row| [row.fetch(:name), row.fetch(:category)] }
      ]

      lib_datasets.each { |dataset_name, dataset_category|
        dataset_category ||= 'NULL'
        sql_query = %Q[
          UPDATE visualizations SET category=#{dataset_category} WHERE name='#{dataset_name}' AND (type='table' OR type='remote');
          ]
        updated_rows = Rails::Sequel.connection.fetch(sql_query).update
        CommonDataRedisCache.new.invalidate
        puts "#{updated_rows} datasets named #{dataset_name} set to category #{dataset_category}"
      }
    end

    desc "Set dataset category in Data Library and propagate to all users"
    task :set_dataset_category, [:dataset_name, :dataset_category] => [:environment] do |t, args|
      require_relative '../../app/helpers/common_data_redis_cache'
      require_relative '../../app/services/visualization/common_data_service'

      sql_query = %Q[
        UPDATE visualizations SET category=#{args[:dataset_category]} WHERE name='#{args[:dataset_name]}' AND (type='table' OR type='remote');
      ]
      updated_rows = Rails::Sequel.connection.fetch(sql_query).update
      CommonDataRedisCache.new.invalidate
      puts "#{updated_rows} datasets named #{args[:dataset_name]} set to category #{args[:dataset_category]}"
    end

    desc "Set dataset category by name in Data Library and propagate to all users"
    task :set_dataset_category_by_name, [:dataset_name, :dataset_category_name] => [:environment] do |t, args|
      require_relative '../../app/helpers/common_data_redis_cache'
      require_relative '../../app/services/visualization/common_data_service'

      category_records = Rails::Sequel.connection.fetch(%Q[
          SELECT id FROM visualization_categories WHERE type=1 AND name='#{args[:dataset_category_name]}';
        ]).all

      if category_records.length == 1
        sql_query = %Q[
          UPDATE visualizations SET category=#{category_records[0][:id]} WHERE name='#{args[:dataset_name]}' AND (type='table' OR type='remote');
        ]
        updated_rows = Rails::Sequel.connection.fetch(sql_query).update
        CommonDataRedisCache.new.invalidate
        puts "#{updated_rows} datasets named #{args[:dataset_name]} set to category #{args[:dataset_category_name]}"
      else
        puts "Error!: #{category_records.length} categories found with name #{args[:dataset_category_name]}"
      end
    end

    desc "Sync dataset aliases for user"
    task :sync_dataset_aliases_for_user, [:dataset_name, :username] => [:environment] do |t, args|
      require_relative '../../app/helpers/common_data_redis_cache'
      require_relative '../../app/services/visualization/common_data_service'

      common_data_user = Cartodb.config[:common_data]["username"]

      lib_datasets = Hash[
        Rails::Sequel.connection.fetch(%Q[
          SELECT name_alias, column_aliases FROM user_tables WHERE
            user_id=(SELECT id FROM users WHERE username='#{common_data_user}')
            AND name='#{args[:dataset_name]}';
        ]).all.map { |row| [row.fetch(:name_alias), row.fetch(:column_aliases)] }
      ]

      lib_datasets.each { |name_alias, column_aliases|
        column_aliases ||= {}
        sql_query = %Q[
          UPDATE user_tables SET name_alias='#{name_alias}', column_aliases='#{column_aliases}'::json WHERE
            user_id=(SELECT id FROM users WHERE username='#{args[:username]}') AND name='#{args[:dataset_name]}';
          ]
        updated_rows = Rails::Sequel.connection.fetch(sql_query).update
        puts "#{updated_rows} datasets named #{args[:dataset_name]} updated for user #{args[:username]}"
      }
    end

    desc "Sync dataset aliases for all users"
    task :sync_dataset_aliases, [:dataset_name] => [:environment] do |t, args|
      require_relative '../../app/helpers/common_data_redis_cache'
      require_relative '../../app/services/visualization/common_data_service'

      common_data_user = Cartodb.config[:common_data]["username"]

      lib_datasets = Hash[
        Rails::Sequel.connection.fetch(%Q[
          SELECT name_alias, column_aliases FROM user_tables WHERE
            user_id=(SELECT id FROM users WHERE username='#{common_data_user}')
            AND name='#{args[:dataset_name]}';
        ]).all.map { |row| [row.fetch(:name_alias), row.fetch(:column_aliases)] }
      ]

      lib_datasets.each { |name_alias, column_aliases|
        column_aliases ||= {}
        sql_query = %Q[
          UPDATE user_tables SET name_alias='#{name_alias}', column_aliases='#{column_aliases}'::json WHERE
            name='#{args[:dataset_name]}' AND user_id <> (SELECT id FROM users WHERE username='#{common_data_user}');
          ]
        updated_rows = Rails::Sequel.connection.fetch(sql_query).update
        puts "Aliases for dataset named #{args[:dataset_name]} updated for #{updated_rows} users"
      }
    end

    desc "Sync dataset description, source, category, exportability and aliases set in Data Library to all users"
    task :sync_dataset_props, [:dataset_name, :props] => [:environment] do |t, args|
      if ENV['verbose'] != "true"
        ActiveRecord::Base.logger = nil
      end

      name = args[:dataset_name]
      valid_viz_props = ['description', 'source', 'category', 'exportable', 'export_geom']
      valid_table_props = ['name_alias', 'column_aliases']
      viz_prop_list = args[:props] ?
                          args[:props].split(';').reject { |prop| !valid_viz_props.include? prop } :
                          valid_viz_props
      table_prop_list = args[:props] ?
                          args[:props].split(';').reject { |prop| !valid_table_props.include? prop } :
                          valid_table_props
      common_data_username = Cartodb.config[:common_data]["username"]
      lib_datasets = {}

      common_data_user = Carto::User.find_by_username(common_data_username)
      Carto::Visualization.where(user_id: common_data_user.id, type: 'table', privacy: 'public', name: name).each do |vis|
        category = vis.vis_category
        user_table = vis.user_table
        lib_datasets[vis.name] = {
          description: vis.description,
          source: vis.source,
          category: category ? category.id : nil,
          exportable: vis.exportable,
          export_geom: vis.export_geom,
          name_alias: user_table.name_alias,
          column_aliases: user_table.column_aliases
        }
      end

      if lib_datasets.count == 1 && (!viz_prop_list.empty? || !table_prop_list.empty?)
        dataset = lib_datasets[name]

        unless viz_prop_list.empty?
          # only update datasets with same name and imported from library, skip library user
          vis_ids = Carto::Visualization.includes(synchronization: :external_data_imports)
            .where(type: 'table', name: name)
            .where('external_data_imports.id IS NOT NULL')
            .where('visualizations.user_id <> ?', common_data_user.id)
            .select('visualizations.id')
            .all
          vis_ids += Carto::Visualization
            .where(type: 'remote', name: name)
            .select('visualizations.id')
            .all

          if vis_ids.empty?
            puts "Warning! No datasets with name '#{name}' found in user accounts"
          else
            props_to_update = Hash.new
            viz_prop_list.each do |prop|
              sym = prop.to_sym
              props_to_update[sym] = dataset[sym]
            end
            puts "Updating visualization properties: #{props_to_update.to_json}"
            updated_rows = Carto::Visualization.where(id: vis_ids).update_all(props_to_update)
            puts "#{updated_rows} visualizations with name '#{name}' updated"
          end
        end

        unless table_prop_list.empty?
          # only update dataset tables with same name and imported from library, skip library user
          ut_ids = Carto::UserTable.includes(map: { visualization: { synchronization: :external_data_imports }})
            .where(name: name)
            .where('external_data_imports.id IS NOT NULL')
            .where('user_tables.user_id <> ?', common_data_user.id)
            .select('user_tables.id')
            .all

          if ut_ids.empty?
            puts "Warning! No user tables with name '#{name}' found in user accounts"
          else
            props_to_update = Hash.new
            table_prop_list.each do |prop|
              sym = prop.to_sym
              props_to_update[sym] = dataset[sym]
            end
            puts "Updating table properties: #{props_to_update.to_json}"
            updated_rows = Carto::UserTable.where(id: ut_ids).update_all(props_to_update)
            puts "#{updated_rows} tables with visualization '#{name}' updated"
          end
        end
      else
        puts "Error! Invalid arguments. Valid properties are: #{valid_props.join(', ')}"
      end
    end

    desc "Create Sample Map"
    task :create_sample_map, [:map_name, :dataset_names] => [:environment] do |t, args|
      CONNECT_TIMEOUT = 45
      DEFAULT_TIMEOUT = 60

      map_name = args[:map_name]
      dataset_names = args[:dataset_names].split(';')
      common_data_username = Cartodb.config[:common_data]["username"]
      common_data_base_url = Cartodb.config[:common_data]["base_url"]
      sample_maps_username = Cartodb.config[:map_samples]["username"]
      common_data_user = Carto::User.find_by_username(common_data_username)
      sample_maps_user = Carto::User.find_by_username(sample_maps_username)
      base_url = CartoDB.base_url(sample_maps_user.subdomain)
      any_import_failed = false

      dataset_names.each do |dataset_name|
        vis = Carto::Visualization.where(type: 'table', name: dataset_name, user_id: common_data_user.id).first

        params = {
          "api_key" => sample_maps_user.api_key,
          "interval" => Carto::ExternalSource::REFRESH_INTERVAL, "type_guessing" => true, "create_vis" => false,
          "remote_visualization_id" => vis.id,
          "fdw" => "driver=postgres;channel=postgres_fdw;table=#{dataset_name}",
          "value" => dataset_name,
          "needs_cd_import" => true, "format" => "json", "controller" => "api/json/synchronizations",
          "action" => "create", "user_domain" => sample_maps_user.subdomain
        }

        http_client = Carto::Http::Client.get('create_sample_map', log_requests: true)
        response = http_client.post(base_url + '/api/v1/synchronizations', {
            headers: { "Content-Type" => "application/json" },
            body: params.to_json,
            connecttimeout: CONNECT_TIMEOUT,
            timeout: DEFAULT_TIMEOUT,
        })
        
        if response.code == 200
          res = JSON.parse(response.body, object_class: OpenStruct)
          job_id = res.data_import.item_queue_id if res.data_import
          import_job = Carto::DataImport.where(id: job_id).first
          until import_job.state == 'complete'
            puts "Import job not complete yet: #{import_job.state}"
            sleep 2
            import_job.reload
          end
        else
          any_import_failed = true
          puts "Synchronization failed: #{response.code}\n#{response.body}"
        end
      end

      unless any_import_failed
        params = {
          "api_key" => sample_maps_user.api_key,
          "name" => map_name, "type" => "derived", "locked" => "true", "tables" => dataset_names,
          "transition_options" => { "time" => 0 }
        }
              
        http_client = Carto::Http::Client.get('create_sample_map', log_requests: true)
        response = http_client.post(base_url + '/api/v1/viz', {
            headers: { "Content-Type" => "application/json" },
            body: params.to_json,
            connecttimeout: CONNECT_TIMEOUT,
            timeout: DEFAULT_TIMEOUT,
        })

        if response.code == 200
          puts "Sample map created successfully"
        else
          puts "Sample map creation failed: #{response.code}"
        end
      end
    end

    def get_visualizations_api_url
      common_data_config = Cartodb.config[:common_data]
      username = common_data_config["username"]
      base_url = common_data_config["base_url"].nil? ? CartoDB.base_url(username) : common_data_config["base_url"]
      base_url + "/api/v1/viz?type=table&privacy=public"
    end

    # Removes common data visualizations from users which have not seen activity in some time
    # e.g: rake cartodb:remotes:remove_from_inactive_users[365,90] will affect all users
    # whose last activity was between 1 year and 3 months ago
    desc 'Remove common data visualizations from inactive users'
    task :remove_from_inactive_users, [:start_days_ago, :end_days_ago] => :environment do |_t, args|
      start_days_ago = args[:start_days_ago].try(:to_i) || 365 * 2
      end_days_ago = args[:end_days_ago].try(:to_i) || 30 * 3
      raise 'Invalid date interval' unless start_days_ago > end_days_ago && end_days_ago > 0
      start_date = DateTime.now - start_days_ago
      end_date = DateTime.now - end_days_ago

      puts "Removing common data visualizations for users with last activity between #{start_date} and #{end_date}"
      query = Carto::User.where("COALESCE(dashboard_viewed_at, created_at) BETWEEN '#{start_date}' AND '#{end_date}'")
                         .where(account_type: Carto::AccountType::FREE)
      user_count = query.count
      puts "#{user_count} users will be affected. Starting in 10 seconds unless canceled (ctrl+C)"
      sleep 10

      processed = 0
      query.find_each do |user|
        processed += 1
        puts "#{user.username} (#{processed} / #{user_count})"
        user.update_column(:last_common_data_update_date, nil)

        user.visualizations.where(type: 'remote').each do |v|
          begin
            unless v.external_source
              puts "  Remote visualization #{v.id} does not have a external source. Skipping..."
              next
            end
            if v.external_source.external_data_imports.any?
              puts "  Remote visualization #{v.id} has been previously imported. Skipping..."
              next
            end

            v.external_source.delete
            v.delete
          rescue => e
            puts "  Error deleting visualization #{v.id}: #{e.message}"
          end
        end
      end
    end
  end

end
