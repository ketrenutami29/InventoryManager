import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";

actor InventoryManager {
  // Define types
  public type ItemId = Nat;
  
  public type Item = {
    id: ItemId;
    name: Text;
    description: Text;
    quantity: Nat;
    unit: Text;
    category: Text;
    lastUpdated: Time.Time;
  };
  
  public type TransactionType = {
    #inside;
    #out;
  };
  
  public type Transaction = {
    id: Nat;
    itemId: ItemId;
    transactionType: TransactionType;
    quantity: Nat;
    notes: Text;
    timestamp: Time.Time;
  };
  
  // State variables
  private stable var nextItemId : ItemId = 0;
  private stable var nextTransactionId : Nat = 0;
  private stable var itemEntries : [(ItemId, Item)] = [];
  private stable var transactionEntries : [(Nat, Transaction)] = [];
  
  // Initialize HashMaps from stable storage
  private var items = HashMap.fromIter<ItemId, Item>(
    itemEntries.vals(), 
    10, 
    Nat.equal, 
    Hash.hash
  );
  
  private var transactions = HashMap.fromIter<Nat, Transaction>(
    transactionEntries.vals(), 
    10, 
    Nat.equal, 
    Hash.hash
  );
  
  // Create a new item
  public func addItem(name : Text, description : Text, quantity : Nat, unit : Text, category : Text) : async ItemId {
    let timestamp = Time.now();
    let item : Item = {
      id = nextItemId;
      name = name;
      description = description;
      quantity = quantity;
      unit = unit;
      category = category;
      lastUpdated = timestamp;
    };
    
    items.put(nextItemId, item);
    
    // Record initial transaction
    if (quantity > 0) {
      let transaction : Transaction = {
        id = nextTransactionId;
        itemId = nextItemId;
        transactionType = #inside;
        quantity = quantity;
        notes = "Initial inventory";
        timestamp = timestamp;
      };
      
      transactions.put(nextTransactionId, transaction);
      nextTransactionId += 1;
    };
    
    let id = nextItemId;
    nextItemId += 1;
    return id;
  };
  
  // Get all items
  public query func getAllItems() : async [Item] {
    Iter.toArray(Iter.map(items.vals(), func (item : Item) : Item { item }))
  };
  
  // Get a specific item
  public query func getItem(id : ItemId) : async ?Item {
    items.get(id)
  };
  
  // Update an item
  public func updateItem(id : ItemId, name : Text, description : Text, unit : Text, category : Text) : async Bool {
    switch (items.get(id)) {
      case (null) { return false; };
      case (?existingItem) {
        let updatedItem : Item = {
          id = id;
          name = name;
          description = description;
          quantity = existingItem.quantity;
          unit = unit;
          category = category;
          lastUpdated = Time.now();
        };
        
        items.put(id, updatedItem);
        return true;
      };
    }
  };
  
  // Record stock transaction (in/out)
  public func recordTransaction(itemId : ItemId, transactionType : TransactionType, quantity : Nat, notes : Text) : async ?Nat {
    switch (items.get(itemId)) {
      case (null) { return null; };
      case (?item) {
        var newQuantity = item.quantity;
        
        // Update item quantity
        switch(transactionType) {
          case (#inside) {
            newQuantity += quantity;
          };
          case (#out) {
            // Check if there's enough stock
            if (quantity > item.quantity) {
              return null; // Not enough stock
            };
            newQuantity -= quantity;
          };
        };
        
        // Update item
        let updatedItem : Item = {
          id = item.id;
          name = item.name;
          description = item.description;
          quantity = newQuantity;
          unit = item.unit;
          category = item.category;
          lastUpdated = Time.now();
        };
        
        items.put(itemId, updatedItem);
        
        // Record transaction
        let timestamp = Time.now();
        let transaction : Transaction = {
          id = nextTransactionId;
          itemId = itemId;
          transactionType = transactionType;
          quantity = quantity;
          notes = notes;
          timestamp = timestamp;
        };
        
        transactions.put(nextTransactionId, transaction);
        let id = nextTransactionId;
        nextTransactionId += 1;
        
        return ?id;
      };
    }
  };
  
  // Get all transactions
  public query func getAllTransactions() : async [Transaction] {
    Iter.toArray(Iter.map(transactions.vals(), func (tx : Transaction) : Transaction { tx }))
  };
  
  // Get transactions for a specific item
  public query func getItemTransactions(itemId : ItemId) : async [Transaction] {
    let txs = Iter.toArray(transactions.vals());
    Array.filter(txs, func (tx : Transaction) : Bool { tx.itemId == itemId })
  };
  
  // Search items by name or category
  public query func searchItems(msg : Text) : async [Item] {
    let searchQuery = Text.toLowercase(msg);
    let filterItems = func (item : Item) : Bool {
      let nameLower = Text.toLowercase(item.name);
      let descLower = Text.toLowercase(item.description);
      let categoryLower = Text.toLowercase(item.category);
      
      Text.contains(nameLower, #text searchQuery) or 
      Text.contains(descLower, #text searchQuery) or
      Text.contains(categoryLower, #text searchQuery)
    };
    
    Iter.toArray(
      Iter.filter(items.vals(), filterItems)
    )
  };
  
  // Get low stock items (below threshold)
  public query func getLowStockItems(threshold : Nat) : async [Item] {
    let filterItems = func (item : Item) : Bool {
      item.quantity <= threshold
    };
    
    Iter.toArray(
      Iter.filter(items.vals(), filterItems)
    )
  };
  
  // For persistence when upgrading
  system func preupgrade() {
    itemEntries := Iter.toArray(items.entries());
    transactionEntries := Iter.toArray(transactions.entries());
  };
  
  system func postupgrade() {
    itemEntries := [];
    transactionEntries := [];
  };
}