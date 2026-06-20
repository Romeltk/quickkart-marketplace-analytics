import streamlit as st
import pandas as pd
import plotly.express as px

st.title("QuickKart Dashboard")

# Load pre-aggregated tables 
@st.cache_data
def load_data():
    monthly = pd.read_csv("monthly_metrics.csv")
    city    = pd.read_csv("city_metrics.csv")
    carrier = pd.read_csv("carrier_metrics.csv")
    return monthly, city, carrier

monthly, city_df, carrier_df = load_data()

# Sidebar filters 
st.sidebar.header("Filters")

selected_cities = st.sidebar.multiselect(
    "City",
    sorted(monthly["city"].unique()),
    default=sorted(monthly["city"].unique())
)

selected_months = st.sidebar.multiselect(
    "Month",
    sorted(monthly["month"].unique()),
    default=sorted(monthly["month"].unique())
)

metric = st.sidebar.selectbox(
    "Metric",
    ["GMV", "Orders", "Repeat Rate", "Delayed Order Rate"]
)

metric_map = {
    "GMV":                "gmv",
    "Orders":             "orders",
    "Repeat Rate":        "repeat_rate",
    "Delayed Order Rate": "delayed_order_rate",
}
col = metric_map[metric]

# Apply filters 
filtered_monthly = monthly[
    monthly["city"].isin(selected_cities) &
    monthly["month"].isin(selected_months)
]

filtered_city = city_df[city_df["city"].isin(selected_cities)]

# KPI strip 
gmv         = filtered_monthly["gmv"].sum()
delay_rate  = filtered_monthly["delayed_order_rate"].mean()
repeat_rate = filtered_monthly["repeat_rate"].mean()

c1, c2, c3 = st.columns(3)
c1.metric("GMV",                f"₹{gmv:,.0f}")
c2.metric("Delayed Order Rate", f"{delay_rate:.1%}")
c3.metric("Repeat Rate",        f"{repeat_rate:.1%}")

# Time series chart 
time_series = (
    filtered_monthly
    .groupby("month")[col]
    .sum() if col in ["gmv", "orders"] else
    filtered_monthly.groupby("month")[col].mean()
).reset_index()

fig = px.line(time_series, x="month", y=col)
st.plotly_chart(fig, use_container_width=True)

# Breakdown chart 
breakdown = st.radio("Breakdown By", ["City", "Carrier"])

if breakdown == "City":
    fig = px.bar(filtered_city, x="city", y=col)
else:
    fig = px.bar(carrier_df, x="carrier", y=col)

st.plotly_chart(fig, use_container_width=True)

# Insights 
st.subheader("Insights")

top_city      = filtered_city.set_index("city")["gmv"].idxmax()
highest_delay = carrier_df.set_index("carrier")["delayed_order_rate"].idxmax()

st.markdown(f"""
- Highest GMV comes from **{top_city}**.
- Carrier with highest delay rate is **{highest_delay}**.
- Current delayed order rate is **{delay_rate:.1%}**.
- Repeat purchase rate is **{repeat_rate:.1%}**.
""")
