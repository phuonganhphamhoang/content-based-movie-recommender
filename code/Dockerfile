FROM python:3.12

EXPOSE 8080
WORKDIR /app_final

COPY . ./

RUN pip install -r requirements.txt

ENTRYPOINT ["streamlit", "run", "app_final.py", "--server.port=8080", "--server.address=0.0.0.0"]
