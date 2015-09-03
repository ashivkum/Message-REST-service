# Message-REST-service
Runs Ruby 1.9.3, Rails 4.2.4, and RSpec 3.2.2 for testing

New version: uses Firebase as "database".  Obviously not ideal, but more like a RESTful service now that state is maintained elsewhere than in instance variable.
Performance is not very scalable yet, since I'm limited by what the service can respond with and what speed (on the Firebase free-tier, response times are awful)

TODO => DRY up the code, clean up, write some fresh unit tests since the previous ones have to be tossed because I changed using static arrays to Firebase.
