
const app = Vue.createApp({
    data() {
        return {
            contents: [],
            error: null,
            success: false,
            currentPage: 1,
            itemsPerPage: 10,
            total: 0,
        };
    },

    computed: {
        totalPages() {
            return Math.ceil(this.total / this.itemsPerPage);
        },
        startIndex() {
            return this.total === 0 ? 0 : (this.currentPage - 1) * this.itemsPerPage + 1;
        },
        endIndex() {
            const end = this.currentPage * this.itemsPerPage;
            return end > this.total ? this.total : end;
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
            axios.get(`/api/v1/contrib/kohasuomi/editx?offset=${(this.currentPage - 1) * this.itemsPerPage}&limit=${this.itemsPerPage}`)
                .then(response => {
                    this.total = parseInt(response.headers['x-total-count'], 10);
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
                'NEW': 'Odottaa',
                'PROCESSING': 'Käsitellään',
                'OK': 'Valmis',
                'FAILED': 'Epäonnistui'
            };
            return translations[status] || status;
        },
        getStatusBadgeClass(status) {
            const classes = {
                'NEW': 'badge bg-warning text-dark',
                'PROCESSING': 'badge bg-info',
                'OK': 'badge bg-success',
                'FAILED': 'badge bg-danger'
            };
            return classes[status] || 'badge bg-secondary';
        },
        getStatusIcon(status) {
            const icons = {
                'NEW': 'bi bi-clock-fill',
                'PROCESSING': 'bi bi-arrow-repeat',
                'OK': 'bi bi-check-circle-fill',
                'FAILED': 'bi bi-x-circle-fill'
            };
            return icons[status] || 'bi bi-question-circle-fill';
        },
        goToPage(page) {
            if (page >= 1 && page <= this.totalPages) {
                this.currentPage = page;
                this.fetchContents();
            }
        },
    },
    watch: {
        itemsPerPage() {
            this.currentPage = 1;
            this.fetchContents();
        },
    },
    mounted() {
        this.fetchContents();
    },
});

app.mount('#editxApp');