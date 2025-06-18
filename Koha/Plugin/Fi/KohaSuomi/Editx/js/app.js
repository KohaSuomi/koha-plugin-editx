
const app = Vue.createApp({
    data() {
        return {
            contents: [],
            error: null,
        };
    },

    methods: {


        fetchContents() {
            axios.get(`/api/v1/contrib/kohasuomi/editx`)
                .then(response => {
                    this.contents = response.data;
                })
                .catch(error => {
                    console.error('Error fetching contents:', error);
                    this.error = 'An error occurred while fetching the contents';
                });
        },


        setPending(id) {
            axios.put(`/api/v1/contrib/kohasuomi/editx/${id}?status=pending`)
                .then(() => {
                    alert('Tila päivitetty onnistuneesti');
                    this.fetchContents();
                })
                .catch(error => {
                    console.error('Error updating status:', error);
                    alert('Tilan päivityksessä tapahtui virhe');
                });
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
    },

    mounted() {
        this.fetchContents();
    },
});

app.mount('#editxApp');