
const app = Vue.createApp({
    data() {
        return {
            contents: [],
            error: null,
            success: false,
            currentPage: 1,
            itemsPerPage: 10,
        };
    },

    computed: {
        totalPages() {
            return Math.ceil(this.contents.length / this.itemsPerPage);
        },
        paginatedContents() {
            const start = (this.currentPage - 1) * this.itemsPerPage;
            const end = start + this.itemsPerPage;
            return this.contents.slice(start, end);
        },
        startIndex() {
            return (this.currentPage - 1) * this.itemsPerPage;
        },
        endIndex() {
            const end = this.currentPage * this.itemsPerPage;
            return end > this.contents.length ? this.contents.length : end;
        },
        visiblePages() {
            const pages = [];
            const maxVisible = 5;
            let start = Math.max(1, this.currentPage - Math.floor(maxVisible / 2));
            let end = Math.min(this.totalPages, start + maxVisible - 1);
            
            if (end - start < maxVisible - 1) {
                start = Math.max(1, end - maxVisible + 1);
            }
            
            for (let i = start; i <= end; i++) {
                pages.push(i);
            }
            return pages;
        },
    },

    methods: {
        fetchContents() {
            axios.get(`/api/v1/contrib/kohasuomi/editx`)
                .then(response => {
                    this.contents = response.data;
                })
                .catch(error => {
                    console.error('Error fetching contents:', error);
                    this.error = 'Sisällön hakemisessa tapahtui virhe';
                    this.success = false;
                });
        },
        setStatus(id, status) {
            axios.put(`/api/v1/contrib/kohasuomi/editx/${id}`, { status: status })
                .then(() => {
                    this.success = true;
                    this.error = null;
                    this.fetchContents();
                })
                .catch(error => {
                    console.error('Error updating status:', error);
                    this.error = 'Tilan päivityksessä tapahtui virhe';
                    this.success = false;
                });
        },
        deleteContent(id) {
            if (confirm('Haluatko varmasti poistaa tämän sanoman?')) {
                axios.delete(`/api/v1/contrib/kohasuomi/editx/${id}`)
                    .then(() => {
                        this.success = true;
                        this.error = null;
                        this.fetchContents();
                    })
                    .catch(error => {
                        console.error('Error deleting content:', error);
                        this.error = 'Sanoman poistamisessa tapahtui virhe';
                        this.success = false;
                    });
            }
        },
        translateStatus(status) {
            const translations = {
                'pending': 'Odottaa',
                'processing': 'Käsitellään',
                'completed': 'Valmis',
                'failed': 'Epäonnistui'
            };
            return translations[status] || status;
        },
        getStatusBadgeClass(status) {
            const classes = {
                'pending': 'badge bg-warning text-dark',
                'processing': 'badge bg-info',
                'completed': 'badge bg-success',
                'failed': 'badge bg-danger'
            };
            return classes[status] || 'badge bg-secondary';
        },
        getStatusIcon(status) {
            const icons = {
                'pending': 'bi bi-clock-fill',
                'processing': 'bi bi-arrow-repeat',
                'completed': 'bi bi-check-circle-fill',
                'failed': 'bi bi-x-circle-fill'
            };
            return icons[status] || 'bi bi-question-circle-fill';
        },
        goToPage(page) {
            if (page >= 1 && page <= this.totalPages) {
                this.currentPage = page;
            }
        },
    },
    watch: {
        itemsPerPage() {
            this.currentPage = 1;
        },
    },
    mounted() {
        this.fetchContents();
    },
});

app.mount('#editxApp');