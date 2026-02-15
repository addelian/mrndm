# mrndm

## purpose

- call mrndm
- get the thought out of your head
- move on with your day

## quickstart

1. run `(path/to/script)/mrndm.sh init` and follow the instructions
2. run `mrndm register` to create an account
3. run `mrndm "hey earth!"` to save your first memo
4. run `mrndm view` to view the memo you just created
5. run `mrndm help` to learn more about mrndm

## usage

### account commands

`(path/to/script)/mrndm.sh init` (alias: `mrndm -i`)

- installs mrndm on your PATH and creates a config file, run this before you do anything else

`mrndm register` (alias: `mrndm -r`)

- registers a username and password and uses them to retrieve a token, which is saved to the config file

`mrndm sync` (alias: `mrndm login`)

- run this when you're using mrndm on a new device for the first time or to regenerate a stale token (will prompt for username & password)

`mrndm logout` (alias: `mrndm -lo`)

- log out of your current mrndm session and removes your session token from the config file

`mrndm logoutall` (alias: `mrndm -la`)

- logs out of all sessions everywhere (including your current one) and stales all existing tokens

`mrndm forgotpassword` (alias: `mrndm -fp`)

- initiates the password reset process (sends an email with instructions)
- not possible without an email assigned to your account

`mrndm user` (alias: `mrndm me`)

- shows information about your account (username, email if present)

`mrndm changeemail`

- changes (or adds) the email associated with your account (which is used solely for password recovery)

`mrndm deleteaccount`

- deletes your account and all associated memos
- irreversible action

### memo-writing examples

`mrndm "we should swap christmas and valentine's day"`

- save this memo and assign the MISC category by default

`mrndm "call congress about swapping christmas and valentine's Day" RMND`

- save this memo and assign the designated RMND category

`mrndm move 2571 TODO`

- moves a memo with the ID 2571 to the RMND category
- memos IDs are immediately associated & made viewable upon saving via `view` commands

`mrndm undo` (alias: `mrndm -z`)

- delete your most recent memo (returns it after deletion)

`mrndm delete #` (alias: `mrndm -d`)

- delete the memo with an ID of # (IDs are assigned upon initial submission)

### memo-retrieving examples

`mrndm view` (alias: `mrndm -v`)

- view your last five memos (sorted by category and with IDs visible)

`mrndm view 1625`

- view the memo with an ID of 1625

`mrndm view WORK`

- view all memos you've saved in the WORK category

`mrndm viewamt 42` (alias: `mrndm -ls`)

- view the last 42 memos you've written

`mrndm view all` (alias: `mrndm -va`)

- view all of your memos 
- i make no promises that this is a good idea

`mrndm help (-h)`

- view the full help screen (which looks suspiciously like this README)

## available categories

- MISC (default)
- RMND
- TODO
- IDEA
- WORK
- TECH
- HOME
- QUOT
- EARS
- EYES
- FOOD
- DRNK