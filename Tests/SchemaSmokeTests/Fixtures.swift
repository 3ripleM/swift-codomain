import Foundation

enum Fixture {
    /// Valid, but un-normalized: padding, mixed case, a blank note, optional keys present and absent.
    static let valid = """
        {
          "title": "  Weekend  ",
          "slug": "Weekend-Plans",
          "owner": { "email": " Ada@Example.com ", "name": "Ada" },
          "sharedWith": [{ "email": "bob@example.com", "name": "Bob" }],
          "settings": { "sort": "Due", "reminderDefault": 15, "timezone": "America/Toronto" },
          "items": [
            {
              "title": "Groceries", "done": false, "priority": "HIGH",
              "due": "2026-10-10T17:00:00Z", "note": "   ", "tags": ["Home", "errands"],
              "reminder": { "at": "2026-10-10T16:00:00Z", "repeats": "weekly" },
              "subtasks": [
                { "title": "Milk", "done": true, "priority": "low", "tags": [], "subtasks": [] },
                {
                  "title": "Bread", "done": false, "priority": "medium", "note": "sourdough", "tags": [],
                  "subtasks": [{ "title": "Check bakery hours", "done": false, "priority": "low", "tags": [], "subtasks": [] }]
                }
              ]
            },
            { "title": "Laundry", "done": false, "priority": "low", "tags": [], "subtasks": [] }
          ]
        }
        """

    /// One failure per line marked ✗; every other value is valid.
    static let invalid = """
        {
          "title": "   ",
          "slug": "weekend plans!",
          "owner": { "email": "ada-at-example.com", "name": "Ada" },
          "sharedWith": [{ "email": "bob@example.com", "name": "Bob" }, { "email": "cy@example.com", "name": " " }],
          "settings": { "sort": "due", "reminderDefault": 0, "timezone": "Mars/Olympus" },
          "items": [
            {
              "title": "Groceries", "done": false, "priority": "urgent", "tags": [],
              "reminder": { "at": "tomorrow", "repeats": "weekly" },
              "subtasks": [
                { "title": "Milk", "done": true, "priority": "low", "tags": [], "subtasks": [] },
                {
                  "title": "\(String(repeating: "x", count: 121))", "done": false, "priority": "low", "tags": [],
                  "subtasks": [{ "title": "Call", "done": false, "priority": "low", "due": "2026-13-45", "tags": [], "subtasks": [] }]
                }
              ]
            },
            { "title": "Laundry", "done": false, "priority": "low", "tags": ["Has Space"], "subtasks": [] }
          ]
        }
        """
}
