# Configuration

After [installing](README.md) the containers, you may need to carry out some of these configuration steps, depending on your tasks.


## Activate once Sign up

Create a user in at http://localhost/

```sh
cd images/
docker compose -f web.yml exec web bash

$ bundle exec rails console
>> user = User.find_by(:display_name => "My New User Name")
=> #[ ... ]
>> user.activate!
=> true
>> quit
```


### Giving Administrator/Moderator Permissions

To give administrator or moderator permissions:

```
$ bundle exec rails console
>> user = User.find_by(:display_name => "My New User Name")
=> #[ ... ]
>> user.roles.create(:role => "administrator", :granter_id => user.id)
=> #[ ... ]
>> user.roles.create(:role => "moderator", :granter_id => user.id)
=> #[ ... ]
>> user.save!
=> true
>> quit
```

Follow the doc for more configuration 👉 https://github.com/openstreetmap/openstreetmap-website/blob/master/CONFIGURE.md