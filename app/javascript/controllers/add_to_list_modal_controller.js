import { Controller } from "@hotwired/stimulus"

// Controls the "Add to List" modal for adding articles to reading lists.
// Provides search/filter functionality, keyboard navigation, and new list creation.
export default class extends Controller {
  static targets = ["searchInput", "listContainer", "emptyState"]
  static values = {
    lists: Array,
    csrfToken: String,
    articleId: Number
  }

  connect() {
    this.selectedIndex = 0
    this.filteredLists = []
  }

  open() {
    this.element.showModal()
    this.searchInputTarget.value = ""
    this.selectedIndex = 0
    this.filter()
    setTimeout(() => this.searchInputTarget.focus(), 50)
  }

  openFromEvent(event) {
    this.articleIdValue = event.detail.articleId
    this.open()
  }

  close() {
    this.element.close()
    this.searchInputTarget.value = ""
  }

  // Filter the list based on search input and re-render
  filter() {
    const query = this.searchInputTarget.value.toLowerCase().trim()

    if (query === "") {
      this.filteredLists = [...this.listsValue]
    } else {
      this.filteredLists = this.listsValue.filter(list =>
        list.title.toLowerCase().includes(query)
      )
    }

    // Check if we need to show "create new" option
    const exactMatch = this.listsValue.some(
      list => list.title.toLowerCase() === query
    )
    this.showCreateOption = query !== "" && !exactMatch

    // Reset selection to first item when filtering
    this.selectedIndex = 0

    this.render()
  }

  // Render the filtered lists
  render() {
    const container = this.listContainerTarget
    container.innerHTML = ""

    const query = this.searchInputTarget.value.trim()

    // Show create new option first if applicable
    if (this.showCreateOption) {
      const createItem = this.createListItem({
        id: "new",
        title: query,
        isCreateNew: true
      }, 0)
      container.appendChild(createItem)
    }

    // Show filtered lists
    this.filteredLists.forEach((list, index) => {
      const adjustedIndex = this.showCreateOption ? index + 1 : index
      const item = this.createListItem(list, adjustedIndex)
      container.appendChild(item)
    })

    // Show/hide empty state
    const hasItems = this.filteredLists.length > 0 || this.showCreateOption
    this.emptyStateTarget.classList.toggle("hidden", hasItems || query === "")

    // Update selection highlight
    this.updateSelection()
  }

  // Create a list item element
  createListItem(list, index) {
    const isSelected = index === this.selectedIndex
    const div = document.createElement("div")
    div.className = `flex items-center justify-between px-2 py-2 rounded mx-2 ${
      isSelected ? "bg-base-200 dark:bg-base-content/10" : "hover:bg-base-200 dark:hover:bg-base-content/5"
    }`
    div.dataset.index = index
    div.dataset.listId = list.id
    div.dataset.action = "click->add-to-list-modal#selectItem"

    const titleSpan = document.createElement("span")
    titleSpan.className = "text-sm font-medium"
    titleSpan.textContent = list.title
    div.appendChild(titleSpan)

    if (list.isCreateNew) {
      const badge = document.createElement("span")
      badge.className = "text-xs text-base-content/50 bg-base-300 dark:bg-base-content/20 px-2 py-1 rounded"
      badge.textContent = "Enter to create"
      div.appendChild(badge)
    }

    return div
  }

  // Update the visual selection state
  updateSelection() {
    const items = this.listContainerTarget.querySelectorAll("[data-index]")
    items.forEach((item) => {
      const index = parseInt(item.dataset.index)
      const isSelected = index === this.selectedIndex
      item.classList.toggle("bg-base-200", isSelected)
      item.classList.toggle("dark:bg-base-content/10", isSelected)
    })
  }

  // Handle keyboard navigation
  handleKeydown(event) {
    const totalItems = this.filteredLists.length + (this.showCreateOption ? 1 : 0)

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        if (totalItems > 0) {
          this.selectedIndex = (this.selectedIndex + 1) % totalItems
          this.updateSelection()
          this.scrollToSelected()
        }
        break

      case "ArrowUp":
        event.preventDefault()
        if (totalItems > 0) {
          this.selectedIndex = (this.selectedIndex - 1 + totalItems) % totalItems
          this.updateSelection()
          this.scrollToSelected()
        }
        break

      case "Enter":
        event.preventDefault()
        this.confirmSelection()
        break

      case "Escape":
        event.preventDefault()
        this.close()
        break
    }
  }

  // Scroll to keep selected item visible
  scrollToSelected() {
    const selectedItem = this.listContainerTarget.querySelector(
      `[data-index="${this.selectedIndex}"]`
    )
    if (selectedItem) {
      selectedItem.scrollIntoView({ block: "nearest", behavior: "smooth" })
    }
  }

  // Handle click selection
  selectItem(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    this.selectedIndex = index
    this.confirmSelection()
  }

  // Confirm the current selection (add to list or create new)
  confirmSelection() {
    const totalItems = this.filteredLists.length + (this.showCreateOption ? 1 : 0)
    if (totalItems === 0) return

    // Check if "create new" option is selected
    if (this.showCreateOption && this.selectedIndex === 0) {
      this.createAndAddToList()
    } else {
      const listIndex = this.showCreateOption
        ? this.selectedIndex - 1
        : this.selectedIndex
      const list = this.filteredLists[listIndex]
      if (list) {
        this.addToList(list.id)
      }
    }
  }

  // Add article to an existing list
  async addToList(listId) {
    try {
      const response = await fetch(`/api/lists/${listId}/articles`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfTokenValue
        },
        body: JSON.stringify({ article_id: this.articleIdValue })
      })

      if (response.ok) {
        this.close()
        window.showFlash("Article added to list", "success")
      } else {
        const data = await response.json()
        window.showFlash(data.error || "Failed to add article", "error")
      }
    } catch (error) {
      console.error("Error adding article to list:", error)
      window.showFlash("Failed to add article", "error")
    }
  }

  // Create a new list and add the article to it
  async createAndAddToList() {
    const title = this.searchInputTarget.value.trim()
    if (!title) return

    try {
      // First create the list
      const createResponse = await fetch("/lists", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfTokenValue
        },
        body: JSON.stringify({ title })
      })

      if (!createResponse.ok) {
        const data = await createResponse.json()
        window.showFlash(data.error || "Failed to create list", "error")
        return
      }

      const listData = await createResponse.json()

      // Update the local lists array for future use
      this.listsValue = [...this.listsValue, { id: listData.id, title: listData.title }]

      // Then add the article to it
      await this.addToList(listData.id)

      // Reload to show new list in sidebar
      window.location.reload()
    } catch (error) {
      console.error("Error creating list:", error)
      window.showFlash("Failed to create list", "error")
    }
  }
}
