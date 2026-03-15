const Gallery = {
  images: [
    "https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1447752875215-b2761acb3c5d?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1433086966358-54859d0ed716?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1472214103451-9374bd1c798e?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1470252649378-9c29740c9fa8?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1490730141103-6cac27aaab94?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1426604966848-d7adac402bff?w=400&h=300&fit=crop",
    "https://images.unsplash.com/photo-1439853949127-fa647821eba0?w=400&h=300&fit=crop"
  ],

  slots: ["img1", "img2", "img3", "img4", "img5", "img6"],
  page: 0,

  get perPage() { return this.slots.length; },
  get totalPages() { return Math.ceil(this.images.length / this.perPage); },

  async loadPage() {
    var start = this.page * this.perPage;
    console.log("[Gallery] loadPage start, page=" + this.page + " start=" + start);

    for (var i = 0; i < this.slots.length; i++) {
      var idx = start + i;

      if (idx < this.images.length) {
        console.log("[Gallery] Loading slot " + this.slots[i] + " idx=" + idx);
        var img = $.getComponentById(this.slots[i]);
        console.log("[Gallery] Component found: " + (img ? img.id : "null"));
        console.log("[Gallery] Calling setResourcePath...");
        var result = img.setResourcePath(this.images[idx]);
        console.log("[Gallery] setResourcePath returned: " + typeof result);
        await result;
        console.log("[Gallery] Loaded slot " + this.slots[i]);
      }
    }

    console.log("[Gallery] Updating labels");

    $.getComponentById("pageLabel").setText(
      "Page " + (this.page + 1) + " of " + this.totalPages
    );

    $.getComponentById("statusLabel").setText(
      "Showing " + (start + 1) + "-" +
      Math.min(start + this.perPage, this.images.length) +
      " of " + this.images.length + " images"
    );

    console.log("[Gallery] loadPage complete");
  },

  nextPage() {
    console.log("[Gallery] nextPage");
    if (this.page < this.totalPages - 1) {
      this.page++;
      this.loadPage();
    }
  },

  prevPage() {
    console.log("[Gallery] prevPage");
    if (this.page > 0) {
      this.page--;
      this.loadPage();
    }
  }
};

$.getComponentById("prevBtn").on.press = function() { Gallery.prevPage(); };
$.getComponentById("nextBtn").on.press = function() { Gallery.nextPage(); };

$.onReady(async () => {
  console.log("[Gallery] onReady fired");
  console.log("[Gallery] images: " + Gallery.images.length);
  console.log("[Gallery] slots: " + Gallery.slots.length);
  Gallery.loadPage();
  console.log("[Gallery] loadPage called (async, returned immediately)");
});

$.onExit = function() {
  console.log("[Gallery] Goodbye!");
};